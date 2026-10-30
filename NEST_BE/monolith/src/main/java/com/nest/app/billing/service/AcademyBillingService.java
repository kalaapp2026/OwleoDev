package com.nest.app.billing.service;

import com.nest.app.fees.gateway.RazorpayGateway;
import com.nest.common.exception.ResourceNotFoundException;
import com.nest.common.security.TenantContext;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

/**
 * What an academy admin sees on Billing and subscription: every plan Owleo offers with the academy's own highlighted, the
 * add-ons on sale with the ones the academy has taken highlighted, and its bills with the GST, the lines, what was paid
 * and what is still owed. Read only; paying goes through {@link SubscriptionPaymentService}.
 */
@Service
public class AcademyBillingService {

    private final JdbcTemplate jdbc;
    private final RazorpayGateway gateway;

    public AcademyBillingService(JdbcTemplate jdbc, RazorpayGateway gateway) {
        this.jdbc = jdbc;
        this.gateway = gateway;
    }

    @Transactional(readOnly = true)
    public Map<String, Object> overview() {
        UUID academyId = TenantContext.currentAcademyId();
        var academy = jdbc.queryForList("SELECT name, plan FROM academies WHERE id = ?", academyId).stream().findFirst()
                .orElseThrow(() -> new ResourceNotFoundException("Academy not found."));
        String planCode = (String) academy.get("plan");

        Map<String, Object> out = new LinkedHashMap<>();
        out.put("academy", academy.get("name"));
        out.put("students", count("SELECT count(*) FROM academy_memberships WHERE academy_id = ? AND role_type = 'STUDENT' AND status = 'ACTIVE'", academyId));
        out.put("trainers", count("SELECT count(*) FROM academy_memberships WHERE academy_id = ? AND role_type = 'TRAINER' AND status = 'ACTIVE'", academyId));
        out.put("plans", plans(planCode));
        out.put("addons", addons(academyId));

        List<Map<String, Object>> invoices = invoices(academyId);
        BigDecimal outstanding = BigDecimal.ZERO;
        int overdue = 0;
        for (var i : invoices) {
            if (Boolean.TRUE.equals(i.get("payable"))) {
                outstanding = outstanding.add((BigDecimal) i.get("balance"));
                if (Boolean.TRUE.equals(i.get("overdue"))) overdue++;
            }
        }
        out.put("invoices", invoices);
        out.put("outstanding", outstanding);
        out.put("overdueCount", overdue);

        Map<String, Object> pay = new LinkedHashMap<>();
        pay.put("enabled", gateway.configured());
        pay.put("provider", gateway.configured() ? "RAZORPAY" : "NONE");
        out.put("payment", pay);
        return out;
    }

    private List<Map<String, Object>> plans(String current) {
        return jdbc.query("""
                SELECT code, display_name, monthly_price, max_students, max_trainers, tone, popular, modules
                FROM billing_plans WHERE active ORDER BY monthly_price, display_name""", (rs, i) -> {
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("code", rs.getString("code"));
            m.put("name", rs.getString("display_name"));
            m.put("price", rs.getBigDecimal("monthly_price"));
            m.put("maxStudents", rs.getObject("max_students"));
            m.put("maxTrainers", rs.getObject("max_trainers"));
            m.put("tone", rs.getString("tone"));
            m.put("popular", rs.getBoolean("popular"));
            String mods = rs.getString("modules");
            m.put("modules", mods == null || mods.isBlank() ? List.of() : Arrays.asList(mods.split(",")));
            m.put("current", rs.getString("code").equals(current));
            return m;
        });
    }

    /** Every add-on on sale, plus any the academy still has that is no longer sold; the academy's own come with "adopted". */
    private List<Map<String, Object>> addons(UUID academyId) {
        return jdbc.query("""
                SELECT d.id, d.name, d.description, d.price, d.billing, d.on_sale, x.from_period
                FROM hq_addons d LEFT JOIN academy_addons x ON x.addon_id = d.id AND x.academy_id = ?
                WHERE d.on_sale OR x.addon_id IS NOT NULL
                ORDER BY (x.addon_id IS NULL), d.name""", (rs, i) -> {
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("id", rs.getObject("id").toString());
            m.put("name", rs.getString("name"));
            m.put("description", rs.getString("description"));
            m.put("price", rs.getBigDecimal("price"));
            m.put("billing", rs.getString("billing").toLowerCase());
            m.put("adopted", rs.getString("from_period") != null);
            m.put("fromPeriod", rs.getString("from_period"));
            m.put("onSale", rs.getBoolean("on_sale"));
            return m;
        }, academyId);
    }

    private List<Map<String, Object>> invoices(UUID academyId) {
        LocalDate today = LocalDate.now();
        List<Map<String, Object>> out = new ArrayList<>();
        for (var r : jdbc.queryForList("""
                SELECT i.id, i.number, i.period, i.plan_code, i.status, i.issued_on, i.due_on, i.discount, i.gst, i.gst_rate, i.total, i.note,
                       COALESCE((SELECT SUM(p.amount) FROM invoice_payments p WHERE p.invoice_id = i.id), 0) AS paid
                FROM academy_invoices i WHERE i.academy_id = ? ORDER BY i.period DESC, i.number DESC""", academyId)) {
            UUID id = (UUID) r.get("id");
            BigDecimal total = (BigDecimal) r.get("total"), paid = (BigDecimal) r.get("paid");
            BigDecimal balance = total.subtract(paid).max(BigDecimal.ZERO);
            String status = (String) r.get("status");
            LocalDate due = ((java.sql.Date) r.get("due_on")).toLocalDate();
            boolean payable = !"WAIVED".equals(status) && balance.signum() > 0;
            boolean overdue = payable && due.isBefore(today);

            Map<String, Object> m = new LinkedHashMap<>();
            m.put("id", id.toString());
            m.put("number", r.get("number"));
            m.put("period", r.get("period"));
            m.put("planCode", r.get("plan_code"));
            m.put("status", status);
            m.put("issuedOn", r.get("issued_on").toString());
            m.put("dueOn", due.toString());
            m.put("overdue", overdue);
            m.put("daysOverdue", overdue ? ChronoUnit.DAYS.between(due, today) : 0);
            m.put("payable", payable);
            m.put("discount", r.get("discount"));
            m.put("gst", r.get("gst"));
            m.put("gstRate", r.get("gst_rate"));
            m.put("total", total);
            m.put("paid", paid);
            m.put("balance", balance);
            m.put("note", r.get("note"));
            m.put("lines", jdbc.queryForList("SELECT kind, label, amount FROM invoice_lines WHERE invoice_id = ? ORDER BY created_at, id", id));
            m.put("payments", jdbc.query("""
                    SELECT paid_on, amount, mode, reference, source FROM invoice_payments WHERE invoice_id = ? ORDER BY paid_on, created_at""", (rs, n) -> {
                Map<String, Object> p = new LinkedHashMap<>();
                p.put("paidOn", rs.getDate("paid_on").toString());
                p.put("amount", rs.getBigDecimal("amount"));
                p.put("mode", rs.getString("mode"));
                p.put("reference", rs.getString("reference") == null ? "" : rs.getString("reference"));
                p.put("online", "ONLINE".equals(rs.getString("source")));
                return p;
            }, id));
            out.add(m);
        }
        return out;
    }

    private long count(String sql, Object... args) {
        Long n = jdbc.queryForObject(sql, Long.class, args);
        return n == null ? 0 : n;
    }

}
