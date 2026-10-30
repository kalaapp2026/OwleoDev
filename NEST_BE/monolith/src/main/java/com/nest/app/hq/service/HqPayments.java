package com.nest.app.hq.service;

import com.nest.app.fees.gateway.RazorpayGateway;
import com.nest.common.exception.BadRequestException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.sql.Timestamp;
import java.time.YearMonth;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

/**
 * Payments, for the Finance workspace: every rupee that moved through Owleo, and which account each academy is mapped to.
 *
 * <p>Two kinds of money pass through. Subscription payments are academies paying Owleo for its monthly bill (recorded by HQ,
 * or paid online by the academy admin). Student fee payments are students paying their academy through Owleo's gateway;
 * that money is collected for the academy and has to reach the account it is mapped to, which is why the mapping lives here.</p>
 */
@Service
public class HqPayments {

    private static final Set<String> TYPES = Set.of("all", "subscription", "student");
    private static final Set<String> STATUSES = Set.of("all", "paid", "started", "failed");
    private static final Set<String> SOURCES = Set.of("all", "online", "manual");

    private final JdbcTemplate jdbc;
    private final RazorpayGateway gateway;

    public HqPayments(JdbcTemplate jdbc, RazorpayGateway gateway) {
        this.jdbc = jdbc;
        this.gateway = gateway;
    }

    /**
     * The transaction history, newest first (at most 500). [month] is YYYY-MM or null for all time; [type], [status] and
     * [source] are "all" or one value; [academyId] and [q] (a reference, invoice number or academy name) narrow it further.
     */
    @Transactional(readOnly = true)
    public Map<String, Object> transactions(String month, String type, String status, String source, String academyId, String q) {
        String t = lower(type), st = lower(status), so = lower(source);
        if (!TYPES.contains(t) || !STATUSES.contains(st) || !SOURCES.contains(so)) throw new BadRequestException("Unknown filter.");
        if (month != null && !month.isBlank()) {
            try {
                YearMonth.parse(month);
            } catch (Exception e) {
                throw new BadRequestException("Month must look like 2026-10.");
            }
        }
        UUID academy = academyId == null || academyId.isBlank() ? null : UUID.fromString(academyId);
        String needle = q == null ? "" : q.trim().toLowerCase();

        var rows = jdbc.queryForList("""
                SELECT * FROM (
                    SELECT 'subscription' AS type, p.id::text AS id, p.created_at AS at, i.academy_id, a.name AS academy, i.number AS ref_no, p.amount, p.mode,
                           COALESCE(p.reference, '') AS reference, lower(p.source) AS source, 'paid' AS status,
                           COALESCE(u.full_name, 'System') AS by_name, '' AS note
                    FROM invoice_payments p JOIN academy_invoices i ON i.id = p.invoice_id JOIN academies a ON a.id = i.academy_id
                    LEFT JOIN users u ON u.id = p.recorded_by
                  UNION ALL
                    SELECT 'subscription', o.id::text, COALESCE(o.paid_at, o.created_at), o.academy_id, a.name, i.number, o.amount, 'Razorpay',
                           COALESCE(o.provider_payment_id, o.provider_order_id), 'online',
                           CASE o.status WHEN 'PAID' THEN 'paid' WHEN 'FAILED' THEN 'failed' ELSE 'started' END,
                           COALESCE(u.full_name, 'Academy admin'), COALESCE(o.note, '')
                    FROM invoice_payment_orders o JOIN academy_invoices i ON i.id = o.invoice_id JOIN academies a ON a.id = o.academy_id
                    LEFT JOIN users u ON u.id = o.user_id
                    WHERE o.status <> 'PAID' OR o.invoice_payment_id IS NULL
                  UNION ALL
                    SELECT 'student', po.id::text, COALESCE(po.paid_at, po.created_at), po.academy_id, a.name, 'Student fee: ' || lower(po.category), po.amount, 'Razorpay',
                           COALESCE(po.provider_payment_id, po.provider_order_id), 'online',
                           CASE po.status WHEN 'PAID' THEN 'paid' WHEN 'FAILED' THEN 'failed' ELSE 'started' END,
                           COALESCE(u.full_name, 'Student'), ''
                    FROM payment_orders po JOIN academies a ON a.id = po.academy_id LEFT JOIN users u ON u.id = po.user_id
                ) x ORDER BY at DESC LIMIT 5000""");

        List<Map<String, Object>> items = new ArrayList<>();
        BigDecimal subscription = BigDecimal.ZERO, student = BigDecimal.ZERO, online = BigDecimal.ZERO, manual = BigDecimal.ZERO;
        int started = 0, failed = 0;
        for (var r : rows) {
            Timestamp at = (Timestamp) r.get("at");
            String ym = at.toLocalDateTime().toLocalDate().toString().substring(0, 7);
            if (month != null && !month.isBlank() && !ym.equals(month)) continue;
            if (!t.equals("all") && !t.equals(r.get("type"))) continue;
            if (!st.equals("all") && !st.equals(r.get("status"))) continue;
            if (!so.equals("all") && !so.equals(r.get("source"))) continue;
            if (academy != null && !academy.equals(r.get("academy_id"))) continue;
            if (!needle.isEmpty() && !(String.valueOf(r.get("reference")) + " " + r.get("ref_no") + " " + r.get("academy") + " " + r.get("by_name")).toLowerCase().contains(needle)) continue;

            BigDecimal amount = (BigDecimal) r.get("amount");
            if ("paid".equals(r.get("status"))) {
                if ("subscription".equals(r.get("type"))) {
                    subscription = subscription.add(amount);
                    if ("online".equals(r.get("source"))) online = online.add(amount);
                    else manual = manual.add(amount);
                } else {
                    student = student.add(amount);
                }
            } else if ("started".equals(r.get("status"))) {
                started++;
            } else {
                failed++;
            }
            if (items.size() < 500) {
                Map<String, Object> m = new LinkedHashMap<>();
                m.put("id", r.get("id"));
                m.put("type", r.get("type"));
                m.put("at", at.toInstant());
                m.put("academyId", r.get("academy_id").toString());
                m.put("academy", r.get("academy"));
                m.put("ref", r.get("ref_no"));
                m.put("amount", amount);
                m.put("mode", r.get("mode"));
                m.put("reference", r.get("reference"));
                m.put("source", r.get("source"));
                m.put("status", r.get("status"));
                m.put("by", r.get("by_name"));
                m.put("note", r.get("note"));
                items.add(m);
            }
        }

        Map<String, Object> kpis = new LinkedHashMap<>();
        kpis.put("subscription", subscription);
        kpis.put("student", student);
        kpis.put("online", online);
        kpis.put("manual", manual);
        kpis.put("started", started);
        kpis.put("failed", failed);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("items", items);
        out.put("kpis", kpis);
        out.put("academies", jdbc.queryForList("SELECT id::text AS id, name FROM academies WHERE closed_at IS NULL ORDER BY name"));
        return out;
    }

    /**
     * Owleo's own receiving account, and for each academy the bank account and gateway account it is mapped to, with how much
     * has moved through it. A mapped academy has a gateway and merchant id; "bank only" has a bank account but no gateway yet.
     */
    @Transactional(readOnly = true)
    public Map<String, Object> accounts() {
        Map<String, Object> owleo = new LinkedHashMap<>();
        String key = gateway.keyId();
        owleo.put("gateway", "Razorpay");
        owleo.put("connected", gateway.configured());
        owleo.put("webhook", gateway.webhookConfigured());
        owleo.put("mode", key.startsWith("rzp_live_") ? "live" : key.isEmpty() ? "" : "test");
        owleo.put("keyHint", key.length() > 6 ? "…" + key.substring(key.length() - 4) : "");

        List<Map<String, Object>> academies = new ArrayList<>();
        int mapped = 0, bankOnly = 0, none = 0;
        for (var r : jdbc.queryForList("""
                SELECT a.id, a.name, a.plan, a.demo_ends_on, a.status,
                       b.id AS bank_id, b.bank, b.holder, b.account_last4, b.ifsc, b.gateway, b.merchant_id,
                       COALESCE((SELECT SUM(p.amount) FROM invoice_payments p JOIN academy_invoices i ON i.id = p.invoice_id WHERE i.academy_id = a.id), 0) AS subscription_paid,
                       (SELECT max(p.created_at) FROM invoice_payments p JOIN academy_invoices i ON i.id = p.invoice_id WHERE i.academy_id = a.id) AS last_paid,
                       COALESCE((SELECT SUM(po.amount) FROM payment_orders po WHERE po.academy_id = a.id AND po.status = 'PAID'), 0) AS student_collected
                FROM academies a LEFT JOIN academy_bank_accounts b ON b.academy_id = a.id AND b.is_primary
                WHERE a.closed_at IS NULL ORDER BY a.name""")) {
            boolean hasBank = r.get("bank_id") != null;
            boolean gw = r.get("gateway") != null && r.get("merchant_id") != null;
            String state = gw ? "mapped" : hasBank ? "bank" : "none";
            if (gw) mapped++;
            else if (hasBank) bankOnly++;
            else none++;
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("academyId", r.get("id").toString());
            m.put("academy", r.get("name"));
            m.put("demo", r.get("demo_ends_on") != null);
            m.put("state", state);
            m.put("bankId", hasBank ? r.get("bank_id").toString() : null);
            m.put("bank", r.get("bank"));
            m.put("holder", r.get("holder"));
            m.put("last4", r.get("account_last4"));
            m.put("ifsc", r.get("ifsc"));
            m.put("gateway", r.get("gateway"));
            m.put("merchantId", r.get("merchant_id"));
            m.put("subscriptionPaid", r.get("subscription_paid"));
            m.put("lastPaid", r.get("last_paid") == null ? null : ((Timestamp) r.get("last_paid")).toInstant());
            m.put("studentCollected", r.get("student_collected"));
            academies.add(m);
        }
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("owleo", owleo);
        out.put("academies", academies);
        out.put("counts", Map.of("mapped", mapped, "bank", bankOnly, "none", none));
        return out;
    }

    private static String lower(String s) {
        return s == null || s.isBlank() ? "all" : s.toLowerCase();
    }
}
