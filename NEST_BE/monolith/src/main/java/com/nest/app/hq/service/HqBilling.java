package com.nest.app.hq.service;

import com.nest.app.hq.HqAudit;
import com.nest.app.notification.entity.NotificationModule;
import com.nest.app.notification.entity.NotificationType;
import com.nest.app.notification.service.NotificationService;
import com.nest.common.exception.BadRequestException;
import com.nest.common.exception.ResourceNotFoundException;
import com.nest.common.security.TenantContext;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.LocalDate;
import java.time.YearMonth;
import java.util.List;
import java.util.Map;
import java.util.UUID;

/**
 * What academies owe Owleo, and every way that changes: raising the month's bills, recording a
 * payment, adding a charge or credit, applying an offer, moving a due date, and nudging for payment.
 *
 * <p>A bill's money is always derived the same way, in {@link #recompute}:
 * <pre>
 *   gross    = sum of every line (a credit is a negative ADJUSTMENT line)
 *   discount = the applied offer's worth, taken off the recurring part (plan + add-ons)
 *   subtotal = gross - discount          (never below zero)
 *   gst      = subtotal x the rate stored on the bill
 *   total    = subtotal + gst
 *   balance  = total - payments received
 * </pre>
 * Status follows the balance, so it can never disagree with the payments.
 */
@Service
public class HqBilling {

    private static final int PAYMENT_TERM_DAYS = 14;

    private final JdbcTemplate jdbc;
    private final HqAudit audit;
    private final NotificationService notifications;

    public HqBilling(JdbcTemplate jdbc, HqAudit audit, NotificationService notifications) {
        this.jdbc = jdbc;
        this.audit = audit;
        this.notifications = notifications;
    }

    // ---- settings ----

    public BigDecimal gstRate() {
        return setting("gst_percent", "18");
    }

    public BigDecimal setupFee() {
        return setting("setup_fee", "4999");
    }

    private BigDecimal setting(String key, String fallback) {
        List<String> v = jdbc.queryForList("SELECT value FROM hq_settings WHERE key = ?", String.class, key);
        return new BigDecimal(v.isEmpty() ? fallback : v.get(0));
    }

    // ---- raising bills ----

    /** One charge on a bill. kind is PLAN, ADDON, SETUP, COMMISSION, MARKETING or ADJUSTMENT. */
    public record Line(String kind, String label, BigDecimal amount) {
    }

    /**
     * Raises the bills for [period] ('YYYY-MM'): one per live academy on a priced plan, carrying the plan
     * charge, its add-ons and, in the month it went live, the one-off setup fee. Safe to run twice: an
     * academy that already has a bill for the period is skipped, so a retried job never double-charges.
     * An academy only owes for months that began after it existed.
     *
     * @return how many bills were created
     */
    @Transactional
    public int generate(String period) {
        return generate(period, null);
    }

    /** As {@link #generate(String)}, for one academy only: used when an academy goes live mid-month. */
    @Transactional
    public int generate(String period, UUID onlyAcademy) {
        YearMonth month = parse(period);
        LocalDate issued = month.atDay(1);
        // These bills are already visible in the academy's Billing screen, so they count as announced.
        return generate(period, onlyAcademy, issued, PAYMENT_TERM_DAYS, true).size();
    }

    /**
     * The full form: bills are dated [issuedOn] and fall due [dueDays] later. When [announced] is false the
     * bill waits to be sent to the academy's admins (see HqInvoicing); otherwise it is marked as already shown.
     *
     * @return the ids of the bills created
     */
    @Transactional
    public List<UUID> generate(String period, UUID onlyAcademy, LocalDate issuedOn, int dueDays, boolean announced) {
        YearMonth month = parse(period);
        LocalDate due = issuedOn.plusDays(dueDays);
        BigDecimal rate = gstRate();
        List<UUID> created = new java.util.ArrayList<>();

        for (var a : billable(period, onlyAcademy)) {
            UUID academyId = (UUID) a.get("id");
            UUID invoiceId = UUID.randomUUID();
            BigDecimal planPrice = (BigDecimal) a.get("monthly_price");
            jdbc.update("""
                    INSERT INTO academy_invoices (id, academy_id, period, plan_code, amount, status, issued_on, due_on, total, gst_rate, number, sent_at, sent_via)
                    VALUES (?, ?, ?, ?, ?, 'DUE', ?, ?, ?, ?, ?, ?, ?)""",
                    invoiceId, academyId, period, a.get("plan"), planPrice, issuedOn, due, planPrice, rate, nextNumber(period),
                    announced ? new java.sql.Timestamp(System.currentTimeMillis()) : null, announced ? "Shown in Billing" : null);
            for (Line l : standardLines(academyId, period)) {
                line(invoiceId, l.kind(), l.label(), l.amount());
            }
            recompute(invoiceId);
            created.add(invoiceId);
        }
        if (!created.isEmpty()) {
            audit.log("collections", "Raised " + created.size() + " bills for " + period);
        }
        return created;
    }

    /** Live academies on a priced plan that have no bill for [period] yet (all of them, or just [onlyAcademy]). */
    public List<Map<String, Object>> billable(String period, UUID onlyAcademy) {
        YearMonth month = parse(period);
        return jdbc.queryForList("""
                SELECT a.id, a.name, a.plan, p.display_name AS plan_name, p.monthly_price, a.go_live_on, a.owner_name, a.owner_email, a.owner_phone
                FROM academies a JOIN billing_plans p ON p.code = a.plan
                WHERE a.status = 'ACTIVE' AND a.closed_at IS NULL AND a.demo_ends_on IS NULL AND p.monthly_price > 0
                  AND a.created_at < ? AND (?::uuid IS NULL OR a.id = ?::uuid)
                  AND NOT EXISTS (SELECT 1 FROM academy_invoices i WHERE i.academy_id = a.id AND i.period = ?)
                ORDER BY a.name""", java.sql.Timestamp.valueOf(month.atDay(1).plusMonths(1).atStartOfDay()), onlyAcademy, onlyAcademy, period);
    }

    /** The standard charges on an academy's bill for [period]: its plan, its add-ons, and the setup fee in its first month. */
    public List<Line> standardLines(UUID academyId, String period) {
        YearMonth month = parse(period);
        var a = jdbc.queryForList("""
                SELECT a.plan, p.display_name, p.monthly_price, a.go_live_on FROM academies a JOIN billing_plans p ON p.code = a.plan WHERE a.id = ?""", academyId)
                .stream().findFirst().orElseThrow(() -> new ResourceNotFoundException("Academy not found."));
        List<Line> lines = new java.util.ArrayList<>();
        lines.add(new Line("PLAN", a.get("display_name") + " plan", (BigDecimal) a.get("monthly_price")));
        for (var ad : jdbc.queryForList("""
                SELECT d.name, d.price FROM academy_addons x JOIN hq_addons d ON d.id = x.addon_id
                WHERE x.academy_id = ? AND x.from_period <= ?
                  AND (d.billing = 'MONTH' OR x.from_period = ?)
                ORDER BY d.name""", academyId, period, period)) {
            lines.add(new Line("ADDON", (String) ad.get("name"), (BigDecimal) ad.get("price")));
        }
        LocalDate live = a.get("go_live_on") == null ? null : ((java.sql.Date) a.get("go_live_on")).toLocalDate();
        BigDecimal setup = setupFee();
        if (live != null && YearMonth.from(live).equals(month) && setup.signum() > 0) {
            lines.add(new Line("SETUP", "Setup and onboarding", setup));
        }
        return lines;
    }

    private static YearMonth parse(String period) {
        try {
            return YearMonth.parse(period);
        } catch (Exception e) {
            throw new BadRequestException("Period must look like 2026-10");
        }
    }

    private String nextNumber(String period) {
        // Highest suffix + 1, not a count: a deleted bill leaves a gap, and counting would reuse a number.
        Integer n = jdbc.queryForObject(
                "SELECT COALESCE(MAX(substring(number FROM '[0-9]+$')::int), 0) FROM academy_invoices WHERE period = ?", Integer.class, period);
        return "INV-" + period.substring(2, 4) + period.substring(5, 7) + "-" + String.format("%03d", (n == null ? 0 : n) + 1);
    }

    private void line(UUID invoiceId, String kind, String label, BigDecimal amount) {
        jdbc.update("INSERT INTO invoice_lines (invoice_id, kind, label, amount) VALUES (?, ?, ?, ?)", invoiceId, kind, label, amount);
    }

    // ---- the arithmetic ----

    /** Re-derives discount, GST and total from the bill's lines and offer, then re-syncs its status. */
    @Transactional
    public void recompute(UUID invoiceId) {
        var inv = jdbc.queryForList("SELECT gst_rate, offer_id, plan_code FROM academy_invoices WHERE id = ?", invoiceId)
                .stream().findFirst().orElseThrow(() -> new ResourceNotFoundException("Bill not found."));
        BigDecimal rate = (BigDecimal) inv.get("gst_rate");

        BigDecimal gross = BigDecimal.ZERO, recurring = BigDecimal.ZERO, plan = BigDecimal.ZERO;
        for (var l : jdbc.queryForList("SELECT kind, amount FROM invoice_lines WHERE invoice_id = ?", invoiceId)) {
            BigDecimal amt = (BigDecimal) l.get("amount");
            gross = gross.add(amt);
            String kind = (String) l.get("kind");
            if (kind.equals("PLAN") || kind.equals("ADDON")) recurring = recurring.add(amt);
            if (kind.equals("PLAN")) plan = plan.add(amt);
        }

        BigDecimal discount = BigDecimal.ZERO;
        if (inv.get("offer_id") != null) {
            var o = jdbc.queryForList("SELECT type, value FROM hq_offers WHERE id = ?", inv.get("offer_id")).stream().findFirst();
            if (o.isPresent()) {
                BigDecimal v = (BigDecimal) o.get().get("value");
                discount = switch ((String) o.get().get("type")) {
                    case "PCT" -> recurring.multiply(v).divide(BigDecimal.valueOf(100), 0, RoundingMode.HALF_UP);
                    case "FLAT" -> v.min(recurring);
                    default -> plan;
                };
            }
        }
        BigDecimal subtotal = gross.subtract(discount).max(BigDecimal.ZERO);
        BigDecimal gst = subtotal.multiply(rate).divide(BigDecimal.valueOf(100), 0, RoundingMode.HALF_UP);
        BigDecimal total = subtotal.add(gst);

        jdbc.update("UPDATE academy_invoices SET discount = ?, gst = ?, total = ? WHERE id = ?", discount, gst, total, invoiceId);
        syncStatus(invoiceId);
    }

    /** DUE or PAID by the balance; WAIVED is a deliberate write-off and is left alone. */
    @Transactional
    public void syncStatus(UUID invoiceId) {
        var row = jdbc.queryForMap("""
                SELECT i.status, i.total, COALESCE((SELECT SUM(p.amount) FROM invoice_payments p WHERE p.invoice_id = i.id), 0) AS paid,
                       (SELECT max(p.created_at) FROM invoice_payments p WHERE p.invoice_id = i.id) AS last_paid
                FROM academy_invoices i WHERE i.id = ?""", invoiceId);
        if ("WAIVED".equals(row.get("status"))) {
            return;
        }
        BigDecimal paid = (BigDecimal) row.get("paid");
        boolean settled = paid.compareTo((BigDecimal) row.get("total")) >= 0;
        jdbc.update("""
                UPDATE academy_invoices SET status = ?, paid_amount = ?, paid_at = ? WHERE id = ?""",
                settled ? "PAID" : "DUE", paid.signum() == 0 ? null : paid,
                settled ? row.get("last_paid") : null, invoiceId);
    }

    // ---- things a person does to a bill ----

    /** A payment typed in by HQ staff. */
    @Transactional
    public void recordPayment(UUID invoiceId, BigDecimal amount, String mode, String reference, LocalDate paidOn) {
        recordPayment(invoiceId, amount, mode, reference, paidOn, "MANUAL", TenantContext.currentUserIdOrNull());
    }

    /**
     * Records money received against a bill. [source] is MANUAL (typed in) or ONLINE (the academy paid through the
     * gateway); [recordedBy] is who did it, or the payer for an online payment. Returns the new payment's id.
     */
    @Transactional
    public UUID recordPayment(UUID invoiceId, BigDecimal amount, String mode, String reference, LocalDate paidOn, String source, UUID recordedBy) {
        var bill = bill(invoiceId);
        if ("WAIVED".equals(bill.get("status"))) throw new BadRequestException("This bill was waived.");
        if (amount == null || amount.signum() <= 0) throw new BadRequestException("Enter the amount received.");
        BigDecimal balance = balance(invoiceId);
        if (balance.signum() <= 0) throw new BadRequestException("This bill is already paid.");
        if (amount.compareTo(balance) > 0) throw new BadRequestException("That is more than the " + inr(balance) + " still to pay.");
        LocalDate issued = ((java.sql.Date) bill.get("issued_on")).toLocalDate();
        LocalDate day = paidOn == null ? LocalDate.now() : paidOn;
        if (day.isAfter(LocalDate.now())) throw new BadRequestException("The payment date cannot be in the future.");
        if (day.isBefore(issued)) throw new BadRequestException("The payment date is before the bill was issued.");
        if (mode == null || mode.isBlank()) throw new BadRequestException("Say how it was paid.");
        UUID paymentId = jdbc.queryForObject("""
                INSERT INTO invoice_payments (invoice_id, paid_on, amount, mode, reference, recorded_by, source)
                VALUES (?, ?, ?, ?, ?, ?, ?) RETURNING id""", UUID.class, invoiceId, day, amount, mode, blankNull(reference), recordedBy, source);
        jdbc.update("UPDATE academy_invoices SET payment_method = ?, payment_ref = ?, recorded_by = ? WHERE id = ?",
                mode, blankNull(reference), recordedBy, invoiceId);
        syncStatus(invoiceId);
        audit.log("collections", (UUID) bill.get("academy_id"),
                ("ONLINE".equals(source) ? "Received " : "Recorded ") + inr(amount) + " (" + mode + ") on " + bill.get("number"));
        return paymentId;
    }

    /**
     * Adds a line to an unpaid bill. [kind] is ADJUSTMENT (a charge or a credit), MARKETING (the fee for
     * promotion) or COMMISSION (event commission); only an adjustment can be a credit.
     */
    @Transactional
    public void addCharge(UUID invoiceId, String kind, String description, boolean credit, BigDecimal amount) {
        if (!java.util.Set.of("ADJUSTMENT", "MARKETING", "COMMISSION").contains(kind)) throw new BadRequestException("Unknown kind of charge.");
        if (credit && !"ADJUSTMENT".equals(kind)) throw new BadRequestException("Only an adjustment can be a credit.");
        var bill = bill(invoiceId);
        if (balance(invoiceId).signum() <= 0) throw new BadRequestException("A paid bill cannot be changed.");
        if (description == null || description.trim().length() < 3) throw new BadRequestException("Say what it is for.");
        if (amount == null || amount.signum() <= 0) throw new BadRequestException("Enter the amount.");
        line(invoiceId, kind, description.trim(), credit ? amount.negate() : amount);
        recompute(invoiceId);
        audit.log("collections", (UUID) bill.get("academy_id"), (credit ? "Credited " : "Charged ") + inr(amount) + ("ADJUSTMENT".equals(kind) ? "" : " (" + kind.toLowerCase() + ")") + " on " + bill.get("number") + ": " + description.trim());
    }

    @Transactional
    public void setDueDate(UUID invoiceId, LocalDate due) {
        var bill = bill(invoiceId);
        if (balance(invoiceId).signum() <= 0) throw new BadRequestException("A paid bill cannot be changed.");
        if (due == null) throw new BadRequestException("Choose the new due date.");
        if (due.isBefore(((java.sql.Date) bill.get("issued_on")).toLocalDate())) throw new BadRequestException("The due date is before the bill was issued.");
        jdbc.update("UPDATE academy_invoices SET due_on = ? WHERE id = ?", due, invoiceId);
        audit.log("collections", (UUID) bill.get("academy_id"), "Moved the due date of " + bill.get("number") + " to " + due);
    }

    /** Applies (or, with a null offer, removes) an offer on one unpaid bill. */
    @Transactional
    public void setOffer(UUID invoiceId, UUID offerId) {
        var bill = bill(invoiceId);
        if (balance(invoiceId).signum() <= 0) throw new BadRequestException("A paid bill cannot be changed.");
        if (offerId != null) {
            var o = jdbc.queryForList("SELECT code, active, starts_on, ends_on, applies_to, use_limit FROM hq_offers WHERE id = ?", offerId)
                    .stream().findFirst().orElseThrow(() -> new ResourceNotFoundException("Offer not found."));
            LocalDate today = LocalDate.now();
            if (!(Boolean) o.get("active")) throw new BadRequestException("That offer is paused.");
            if (today.isBefore(((java.sql.Date) o.get("starts_on")).toLocalDate()) || today.isAfter(((java.sql.Date) o.get("ends_on")).toLocalDate())) {
                throw new BadRequestException("That offer is not running today.");
            }
            String applies = (String) o.get("applies_to");
            if (!applies.equals("all") && !applies.equals(bill.get("plan_code"))) throw new BadRequestException("That offer is not for this plan.");
            Integer limit = (Integer) o.get("use_limit");
            if (limit != null) {
                Integer used = jdbc.queryForObject("SELECT count(*) FROM academy_invoices WHERE offer_id = ? AND id <> ?", Integer.class, offerId, invoiceId);
                if (used != null && used >= limit) throw new BadRequestException("That offer has been used up.");
            }
            audit.log("collections", (UUID) bill.get("academy_id"), "Applied offer " + o.get("code") + " to " + bill.get("number"));
        } else {
            audit.log("collections", (UUID) bill.get("academy_id"), "Removed the offer from " + bill.get("number"));
        }
        jdbc.update("UPDATE academy_invoices SET offer_id = ? WHERE id = ?", offerId, invoiceId);
        recompute(invoiceId);
    }

    /**
     * Reminds an academy's admins about unpaid bills. Delivery is an in-app notification to each admin of the
     * academy (a real message in their Owleo Nest bell); [channels] is recorded on the bill's history.
     *
     * @return how many people were notified
     */
    @Transactional
    public int remind(UUID academyId, List<UUID> invoiceIds, String channels, String message) {
        if (message == null || message.trim().length() < 10) throw new BadRequestException("Write a short message.");
        if (invoiceIds.isEmpty()) throw new BadRequestException("Nothing is unpaid for this academy.");
        UUID actor = TenantContext.currentUserIdOrNull();
        for (UUID id : invoiceIds) {
            jdbc.update("INSERT INTO invoice_reminders (invoice_id, channels, sent_by, message) VALUES (?, ?, ?, ?)",
                    id, channels, actor, message.trim());
        }
        List<UUID> admins = jdbc.queryForList("""
                SELECT user_id FROM academy_memberships WHERE academy_id = ? AND role_type = 'ACADEMY_ADMIN' AND status = 'ACTIVE'""",
                UUID.class, academyId);
        for (UUID u : admins) {
            notifications.notify(u, NotificationModule.ERP, NotificationType.ADMIN_BROADCAST, "Payment reminder from Owleo", message.trim(), null);
        }
        String name = jdbc.queryForObject("SELECT name FROM academies WHERE id = ?", String.class, academyId);
        audit.log("collections", academyId, "Sent a payment reminder to " + name);
        return admins.size();
    }

    // ---- helpers ----

    private Map<String, Object> bill(UUID id) {
        return jdbc.queryForList("SELECT id, academy_id, number, status, issued_on, plan_code FROM academy_invoices WHERE id = ?", id)
                .stream().findFirst().orElseThrow(() -> new ResourceNotFoundException("Bill not found."));
    }

    public BigDecimal balance(UUID invoiceId) {
        return jdbc.queryForObject("""
                SELECT i.total - COALESCE((SELECT SUM(p.amount) FROM invoice_payments p WHERE p.invoice_id = i.id), 0)
                FROM academy_invoices i WHERE i.id = ?""", BigDecimal.class, invoiceId);
    }

    public static String inr(BigDecimal v) {
        return "₹" + java.text.NumberFormat.getIntegerInstance(new java.util.Locale("en", "IN")).format(v.setScale(0, RoundingMode.HALF_UP));
    }

    private static String blankNull(String s) {
        return s == null || s.isBlank() ? null : s.trim();
    }
}
