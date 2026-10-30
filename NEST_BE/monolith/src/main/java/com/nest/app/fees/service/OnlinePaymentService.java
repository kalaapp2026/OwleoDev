package com.nest.app.fees.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.nest.app.fees.dto.ConfirmOnlinePaymentRequest;
import com.nest.app.fees.dto.OnlineOrderResponse;
import com.nest.app.fees.dto.PayFeeRequest;
import com.nest.app.fees.dto.PayFeeResponse;
import com.nest.app.fees.entity.FeeTransaction;
import com.nest.app.fees.entity.PaymentOrder;
import com.nest.app.fees.gateway.RazorpayGateway;
import com.nest.app.fees.repository.FeeTransactionRepository;
import com.nest.app.fees.repository.PaymentOrderRepository;
import com.nest.common.audit.Auditable;
import com.nest.common.exception.BadRequestException;
import com.nest.common.exception.ConflictException;
import com.nest.common.exception.ForbiddenException;
import com.nest.common.exception.ResourceNotFoundException;
import com.nest.common.security.TenantContext;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.io.IOException;
import java.math.BigDecimal;
import java.time.Instant;
import java.util.Map;
import java.util.UUID;

/**
 * A student paying their own fee through Razorpay.
 *
 * <p>Three rules keep the money honest:</p>
 * <ul>
 *   <li>The amount is the ledger's, computed in {@link StudentPaymentService#resolveDue} - the client
 *       never names one.</li>
 *   <li>Nothing is marked paid on the client's word. A fee settles only when Razorpay's signature
 *       checks out, whether it arrives as the browser's confirmation or as the server-to-server
 *       webhook.</li>
 *   <li>Settling is idempotent: both routes call {@link #settle} on a row-locked order, so the
 *       second to arrive finds it PAID and posts nothing.</li>
 * </ul>
 */
@Service
public class OnlinePaymentService {

    private static final Logger log = LoggerFactory.getLogger(OnlinePaymentService.class);

    private final StudentPaymentService studentPaymentService;
    private final RazorpayGateway gateway;
    private final PaymentOrderRepository orderRepository;
    private final FeeTransactionRepository transactionRepository;
    private final ObjectMapper mapper;

    public OnlinePaymentService(StudentPaymentService studentPaymentService, RazorpayGateway gateway,
                                PaymentOrderRepository orderRepository,
                                FeeTransactionRepository transactionRepository, ObjectMapper mapper) {
        this.studentPaymentService = studentPaymentService;
        this.gateway = gateway;
        this.orderRepository = orderRepository;
        this.transactionRepository = transactionRepository;
        this.mapper = mapper;
    }

    /** Set by Spring. Optional so this class stays constructible on its own: a webhook for one of Owleo's own bills is handed on. */
    private com.nest.app.billing.service.SubscriptionPaymentService subscriptionPayments;

    @org.springframework.beans.factory.annotation.Autowired(required = false)
    public void setSubscriptionPayments(com.nest.app.billing.service.SubscriptionPaymentService subscriptionPayments) {
        this.subscriptionPayments = subscriptionPayments;
    }

    public boolean enabled() {
        return gateway.configured();
    }

    /**
     * Starts a checkout. Deliberately not one transaction: the call to Razorpay can take seconds,
     * and holding a database connection open across it would starve the small pool.
     */
    public OnlineOrderResponse createOrder(PayFeeRequest request) {
        if (!gateway.configured()) {
            throw new ConflictException("Online payments are not enabled for this academy yet.");
        }
        UUID academyId = TenantContext.currentAcademyId();
        UUID membershipId = TenantContext.currentMembershipId();
        StudentPaymentService.Due due = studentPaymentService.resolveDue(request);

        long paise = toPaise(due.amount());
        String providerOrderId = gateway.createOrder(paise, "INR", "nest_" + UUID.randomUUID().toString().replace("-", ""),
                Map.of("academyId", academyId.toString(), "membershipId", membershipId.toString(),
                        "category", due.category().name()));

        orderRepository.save(PaymentOrder.builder()
                .academyId(academyId)
                .membershipId(membershipId)
                .userId(TenantContext.currentUserId())
                .category(due.category())
                .courseId(due.courseId())
                .period(due.period())
                .feeTypeId(due.feeTypeId())
                .studentFeeId(due.studentFeeId())
                .amount(due.amount())
                .amountPaise(paise)
                .provider(RazorpayGateway.PROVIDER)
                .providerOrderId(providerOrderId)
                .build());
        return new OnlineOrderResponse(providerOrderId, gateway.keyId(), paise, due.amount(), "INR");
    }

    /**
     * The browser reporting a finished payment. Safe to call repeatedly - the app retries it if the
     * network drops - and safe if the webhook got there first.
     */
    @Transactional
    @Auditable(action = "STUDENT_FEE_PAID_ONLINE", entityType = "fee_transaction")
    public PayFeeResponse confirm(ConfirmOnlinePaymentRequest request) {
        PaymentOrder order = orderRepository.lockByProviderOrderId(RazorpayGateway.PROVIDER, request.orderId())
                .orElseThrow(() -> new ResourceNotFoundException("Payment not found"));
        // Someone else's order id is "not found", not "forbidden": don't confirm it exists.
        if (!order.getMembershipId().equals(TenantContext.currentMembershipId())) {
            throw new ResourceNotFoundException("Payment not found");
        }
        if (!gateway.verifyCheckoutSignature(request.orderId(), request.paymentId(), request.signature())) {
            throw new ForbiddenException("The payment could not be verified.");
        }
        FeeTransaction tx = settle(order, request.paymentId());
        return new PayFeeResponse(tx.getId(), order.getAmount(), request.paymentId());
    }

    /**
     * Razorpay's server-to-server call. The signature is over the raw bytes, so the caller must pass
     * them untouched. Anything not ours - another product on the same Razorpay account, an event we
     * don't act on - is acknowledged and ignored, so Razorpay doesn't retry it for days.
     *
     * @return false only when the signature is wrong
     */
    @Transactional
    public boolean handleWebhook(byte[] rawBody, String signature) {
        if (!gateway.verifyWebhookSignature(rawBody, signature)) {
            return false;
        }
        JsonNode root;
        try {
            root = mapper.readTree(rawBody);
        } catch (IOException e) {
            throw new BadRequestException("Unreadable webhook body");
        }
        String event = root.path("event").asText("");
        JsonNode payment = root.path("payload").path("payment").path("entity");
        String orderId = payment.path("order_id").asText("");
        String paymentId = payment.path("id").asText("");
        if (orderId.isEmpty() || paymentId.isEmpty()) {
            return true;
        }
        PaymentOrder order = orderRepository.lockByProviderOrderId(RazorpayGateway.PROVIDER, orderId).orElse(null);
        if (order == null) {
            if (subscriptionPayments != null && subscriptionPayments.handleWebhook(event, orderId, paymentId, payment.path("amount").asLong(-1))) {
                return true;   // one of Owleo's own bills, not a student fee
            }
            log.info("Razorpay webhook {} for an order we don't know: {}", event, orderId);
            return true;
        }
        switch (event) {
            case "payment.captured", "order.paid" -> {
                // The signature proves Razorpay sent this; the amount check proves it settles OUR
                // order for the figure we priced, not a smaller payment against the same order id.
                if (payment.path("amount").asLong(-1) != order.getAmountPaise()) {
                    log.warn("Razorpay payment {} amount {} does not match order {} ({}); not settling",
                            paymentId, payment.path("amount").asLong(-1), orderId, order.getAmountPaise());
                    return true;
                }
                settle(order, paymentId);
            }
            case "payment.failed" -> {
                if (order.getStatus() == PaymentOrder.Status.CREATED) {
                    order.setStatus(PaymentOrder.Status.FAILED);
                }
            }
            default -> { }
        }
        return true;
    }

    /** Posts the money to the ledger exactly once. The caller holds the order's row lock. */
    private FeeTransaction settle(PaymentOrder order, String paymentId) {
        if (order.getStatus() == PaymentOrder.Status.PAID) {
            return transactionRepository.findById(order.getFeeTransactionId())
                    .orElseThrow(() -> new IllegalStateException("Paid order " + order.getId() + " has no ledger row"));
        }
        FeeTransaction tx = new StudentPaymentService.Due(order.getCategory(), order.getCourseId(), order.getPeriod(),
                order.getFeeTypeId(), order.getStudentFeeId(), order.getAmount())
                .toTransaction(order.getAcademyId(), order.getMembershipId(), order.getUserId())
                .amountPaid(order.getAmount())
                .gatewayRef(paymentId)
                .note("Paid online (UPI, Razorpay)")
                .build();
        FeeTransaction saved = transactionRepository.saveAndFlush(tx);
        order.setStatus(PaymentOrder.Status.PAID);
        order.setProviderPaymentId(paymentId);
        order.setFeeTransactionId(saved.getId());
        order.setPaidAt(Instant.now());
        orderRepository.save(order);
        return saved;
    }

    static long toPaise(BigDecimal rupees) {
        return rupees.setScale(2, java.math.RoundingMode.HALF_UP).movePointRight(2).longValueExact();
    }
}
