package com.nest.app.billing.service;

import com.nest.app.fees.gateway.RazorpayGateway;
import com.nest.app.hq.service.HqBilling;
import com.nest.app.notification.entity.NotificationModule;
import com.nest.app.notification.entity.NotificationType;
import com.nest.app.notification.service.NotificationService;
import com.nest.common.exception.BadRequestException;
import com.nest.common.exception.ConflictException;
import com.nest.common.exception.ForbiddenException;
import com.nest.common.exception.ResourceNotFoundException;
import com.nest.common.security.TenantContext;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

/**
 * An academy admin paying Owleo's monthly bill through Razorpay. The money goes to Owleo's own Razorpay account, which
 * is the right place for it: Owleo is the one being paid.
 *
 * <p>The same three rules as a student paying a fee keep it honest: the amount is the bill's balance as the server
 * computes it (the client never names one); nothing is marked paid on the client's word, only on Razorpay's
 * signature, from the browser's confirmation or the server-to-server webhook; and settling is idempotent, because
 * both routes lock the order row first and the second to arrive finds it already paid.</p>
 */
@Service
public class SubscriptionPaymentService {

    private static final Logger log = LoggerFactory.getLogger(SubscriptionPaymentService.class);
    /** What the payment is recorded as in Collections. */
    static final String MODE = "Razorpay";

    private final JdbcTemplate jdbc;
    private final RazorpayGateway gateway;
    private final HqBilling billing;
    private final NotificationService notifications;

    public SubscriptionPaymentService(JdbcTemplate jdbc, RazorpayGateway gateway, HqBilling billing, NotificationService notifications) {
        this.jdbc = jdbc;
        this.gateway = gateway;
        this.billing = billing;
        this.notifications = notifications;
    }

    public boolean enabled() {
        return gateway.configured();
    }

    /**
     * Opens a checkout for the whole balance of one of this academy's bills. Not one database transaction: the call to
     * Razorpay can take seconds and should not hold a connection open across it.
     */
    public Map<String, Object> createOrder(UUID invoiceId) {
        if (!gateway.configured()) {
            throw new ConflictException("Online payment is not switched on yet. Pay Owleo directly and ask them to record it.");
        }
        UUID academyId = TenantContext.currentAcademyId();
        var inv = jdbc.queryForList("SELECT id, academy_id, number, status FROM academy_invoices WHERE id = ?", invoiceId).stream().findFirst()
                // Someone else's bill is "not found", not "forbidden": do not confirm it exists.
                .filter(r -> academyId.equals(r.get("academy_id")))
                .orElseThrow(() -> new ResourceNotFoundException("Bill not found."));
        if ("WAIVED".equals(inv.get("status"))) throw new BadRequestException("This bill was waived. Nothing to pay.");
        BigDecimal balance = billing.balance(invoiceId);
        if (balance.signum() <= 0) throw new BadRequestException("This bill is already paid.");

        long paise = toPaise(balance);
        String receipt = "nest_inv_" + UUID.randomUUID().toString().replace("-", "").substring(0, 20);
        String providerOrderId = gateway.createOrder(paise, "INR", receipt,
                Map.of("academyId", academyId.toString(), "invoiceId", invoiceId.toString(), "invoice", String.valueOf(inv.get("number"))));
        jdbc.update("""
                INSERT INTO invoice_payment_orders (invoice_id, academy_id, user_id, amount, amount_paise, provider, provider_order_id)
                VALUES (?, ?, ?, ?, ?, ?, ?)""", invoiceId, academyId, TenantContext.currentUserId(), balance, paise, RazorpayGateway.PROVIDER, providerOrderId);

        Map<String, Object> out = new LinkedHashMap<>();
        out.put("orderId", providerOrderId);
        out.put("keyId", gateway.keyId());
        out.put("amountPaise", paise);
        out.put("amount", balance);
        out.put("currency", "INR");
        out.put("invoice", inv.get("number"));
        return out;
    }

    /** The browser reporting a finished payment. Safe to call repeatedly, and safe if the webhook got there first. */
    @Transactional
    public Map<String, Object> confirm(String orderId, String paymentId, String signature) {
        Map<String, Object> order = lock(orderId);
        if (order == null || !TenantContext.currentAcademyId().equals(order.get("academy_id"))) {
            throw new ResourceNotFoundException("Payment not found.");
        }
        if (!gateway.verifyCheckoutSignature(orderId, paymentId, signature)) {
            throw new ForbiddenException("The payment could not be verified.");
        }
        return settle(order, paymentId);
    }

    /**
     * Razorpay's webhook for an order that is not a student fee. Returns false when the order is not ours at all, so the
     * caller can ignore it. The signature has already been checked.
     */
    @Transactional
    public boolean handleWebhook(String event, String orderId, String paymentId, long amountPaise) {
        Map<String, Object> order = lock(orderId);
        if (order == null) return false;
        switch (event) {
            case "payment.captured", "order.paid" -> {
                if (amountPaise != ((Number) order.get("amount_paise")).longValue()) {
                    log.warn("Razorpay payment {} amount {} does not match bill order {} ({}); not settling", paymentId, amountPaise, orderId, order.get("amount_paise"));
                    return true;
                }
                settle(order, paymentId);
            }
            case "payment.failed" -> jdbc.update("UPDATE invoice_payment_orders SET status = 'FAILED' WHERE id = ? AND status = 'CREATED'", order.get("id"));
            default -> { }
        }
        return true;
    }

    private Map<String, Object> lock(String orderId) {
        return jdbc.queryForList("SELECT * FROM invoice_payment_orders WHERE provider = ? AND provider_order_id = ? FOR UPDATE", RazorpayGateway.PROVIDER, orderId)
                .stream().findFirst().orElse(null);
    }

    /** Posts the money against the bill exactly once. The caller holds the order's row lock. */
    private Map<String, Object> settle(Map<String, Object> order, String paymentId) {
        UUID id = (UUID) order.get("id"), invoiceId = (UUID) order.get("invoice_id"), academyId = (UUID) order.get("academy_id");
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("reference", paymentId);
        if ("PAID".equals(order.get("status"))) {
            out.put("amount", order.get("amount"));
            out.put("alreadySettled", true);
            return out;
        }
        BigDecimal paid = (BigDecimal) order.get("amount");
        BigDecimal balance = billing.balance(invoiceId);
        String note = null;
        UUID paymentRow = null;
        if (balance.signum() <= 0) {
            // The bill was settled another way while this checkout was open. The money has still arrived at Owleo.
            note = "Paid online after the bill was already settled. Refund or credit it.";
        } else {
            BigDecimal applied = paid.min(balance);
            if (applied.compareTo(paid) < 0) note = "Only part of this payment was needed; the rest is a credit to refund.";
            paymentRow = billing.recordPayment(invoiceId, applied, MODE, paymentId, null, "ONLINE", (UUID) order.get("user_id"));
        }
        jdbc.update("""
                UPDATE invoice_payment_orders SET status = 'PAID', provider_payment_id = ?, invoice_payment_id = ?, note = ?, paid_at = now() WHERE id = ?""",
                paymentId, paymentRow, note, id);
        out.put("amount", paid);
        out.put("note", note);
        tell(academyId, invoiceId, paid);
        return out;
    }

    /** Tells the academy's admins the payment landed, so there is a record in their app besides the receipt. */
    private void tell(UUID academyId, UUID invoiceId, BigDecimal amount) {
        try {
            String number = jdbc.queryForObject("SELECT number FROM academy_invoices WHERE id = ?", String.class, invoiceId);
            List<UUID> admins = jdbc.queryForList("""
                    SELECT DISTINCT user_id FROM academy_memberships WHERE academy_id = ? AND role_type = 'ACADEMY_ADMIN' AND status = 'ACTIVE'""", UUID.class, academyId);
            for (UUID u : admins) {
                notifications.notify(u, NotificationModule.ERP, NotificationType.ADMIN_BROADCAST, "Payment received",
                        "We received " + HqBilling.inr(amount) + " for Owleo bill " + number + ". Thank you!", null);
            }
        } catch (RuntimeException e) {
            // A notification problem must never undo a payment.
            log.warn("Could not notify admins of payment on invoice {}: {}", invoiceId, e.getMessage());
        }
    }

    static long toPaise(BigDecimal rupees) {
        return rupees.setScale(2, RoundingMode.HALF_UP).movePointRight(2).longValueExact();
    }
}
