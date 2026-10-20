package com.nest.app.hq.service;

import com.nest.common.exception.ResourceNotFoundException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.YearMonth;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

/** The read side of Collections: the overview, the bill list, one bill, and one academy's account. */
@Service
public class HqCollections {

    private static final List<String> MODES = List.of("Autopay", "UPI", "Card", "Net banking", "Bank transfer", "Cheque", "Cash");

    private final JdbcTemplate jdbc;
    public HqCollections(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    private static final String BILL_SQL = """
            SELECT i.id, i.number, i.academy_id, a.name AS academy, a.plan AS academy_plan, i.plan_code, p.display_name AS plan_name,
                   i.period, i.issued_on, i.due_on, i.total, i.status AS raw_status, i.offer_id,
                   COALESCE((SELECT SUM(pm.amount) FROM invoice_payments pm WHERE pm.invoice_id = i.id), 0) AS paid
            FROM academy_invoices i JOIN academies a ON a.id = i.academy_id LEFT JOIN billing_plans p ON p.code = i.plan_code
            """;

    private Map<String, Object> toBill(java.sql.ResultSet rs, LocalDate today) throws java.sql.SQLException {
        BigDecimal total = rs.getBigDecimal("total"), paid = rs.getBigDecimal("paid");
        BigDecimal balance = total.subtract(paid).max(BigDecimal.ZERO);
        LocalDate due = rs.getDate("due_on").toLocalDate();
        String raw = rs.getString("raw_status");
        String status = "WAIVED".equals(raw) ? "waived" : balance.signum() == 0 ? "paid" : due.isBefore(today) ? "overdue" : "due";
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("id", rs.getObject("id", UUID.class));
        m.put("number", rs.getString("number"));
        m.put("academyId", rs.getObject("academy_id", UUID.class));
        m.put("academy", rs.getString("academy"));
        m.put("planCode", rs.getString("plan_code"));
        m.put("planName", rs.getString("plan_name"));
        m.put("period", rs.getString("period"));
        m.put("issuedOn", rs.getDate("issued_on").toLocalDate());
        m.put("dueOn", due);
        m.put("total", total);
        m.put("paid", paid);
        m.put("balance", balance);
        m.put("status", status);
        m.put("partPaid", paid.signum() > 0 && balance.signum() > 0);
        m.put("daysLate", "overdue".equals(status) ? ChronoUnit.DAYS.between(due, today) : 0);
        m.put("offerId", rs.getObject("offer_id"));
        return m;
    }

    @Transactional(readOnly = true)
    public List<Map<String, Object>> bills(String period, String academyId) {
        LocalDate today = LocalDate.now();
        StringBuilder sql = new StringBuilder(BILL_SQL).append(" WHERE 1 = 1");
        List<Object> args = new ArrayList<>();
        if (period != null && !period.isBlank()) {
            sql.append(" AND i.period = ?");
            args.add(period);
        }
        if (academyId != null && !academyId.isBlank()) {
            sql.append(" AND i.academy_id = ?");
            args.add(UUID.fromString(academyId));
        }
        sql.append(" ORDER BY i.period DESC, a.name");
        return jdbc.query(sql.toString(), (rs, i) -> toBill(rs, today), args.toArray());
    }

    @Transactional(readOnly = true)
    public Map<String, Object> bill(UUID id) {
        LocalDate today = LocalDate.now();
        Map<String, Object> out = jdbc.query(BILL_SQL + " WHERE i.id = ?", (rs, i) -> toBill(rs, today), id)
                .stream().findFirst().orElseThrow(() -> new ResourceNotFoundException("Bill not found."));
        var meta = jdbc.queryForMap("SELECT discount, gst, gst_rate, total FROM academy_invoices WHERE id = ?", id);
        out.put("discount", meta.get("discount"));
        out.put("gst", meta.get("gst"));
        out.put("gstRate", meta.get("gst_rate"));
        out.put("lines", jdbc.queryForList("SELECT id, kind, label, amount FROM invoice_lines WHERE invoice_id = ? ORDER BY created_at, id", id));
        out.put("payments", jdbc.queryForList("""
                SELECT id, paid_on AS "paidOn", amount, mode, reference FROM invoice_payments WHERE invoice_id = ? ORDER BY paid_on, created_at""", id));
        out.put("reminders", jdbc.queryForList("""
                SELECT r.sent_at AS "sentAt", r.channels, r.message, COALESCE(u.full_name, 'System') AS "by"
                FROM invoice_reminders r LEFT JOIN users u ON u.id = r.sent_by WHERE r.invoice_id = ? ORDER BY r.sent_at""", id));
        if (out.get("offerId") != null) {
            out.put("offer", jdbc.queryForMap("SELECT id, name, code, type, value FROM hq_offers WHERE id = ?", out.get("offerId")));
        }
        out.put("availableOffers", jdbc.queryForList("""
                SELECT id, name, code, type, value FROM hq_offers
                WHERE active AND current_date BETWEEN starts_on AND ends_on AND (applies_to = 'all' OR applies_to = ?)
                  AND (use_limit IS NULL OR use_limit > (SELECT count(*) FROM academy_invoices x WHERE x.offer_id = hq_offers.id))
                ORDER BY code""", out.get("planCode")));
        return out;
    }

    /** One academy's payment history, for the account drawer. */
    @Transactional(readOnly = true)
    public Map<String, Object> account(UUID academyId) {
        LocalDate today = LocalDate.now();
        var acad = jdbc.queryForList("SELECT id, name, owner_name, owner_email, email, plan FROM academies WHERE id = ?", academyId)
                .stream().findFirst().orElseThrow(() -> new ResourceNotFoundException("Academy not found."));
        List<Map<String, Object>> bills = jdbc.query(BILL_SQL + " WHERE i.academy_id = ? ORDER BY i.period DESC", (rs, i) -> toBill(rs, today), academyId);
        BigDecimal toPay = BigDecimal.ZERO, overdue = BigDecimal.ZERO, paid = BigDecimal.ZERO;
        for (var b : bills) {
            toPay = toPay.add((BigDecimal) b.get("balance"));
            if ("overdue".equals(b.get("status"))) overdue = overdue.add((BigDecimal) b.get("balance"));
            paid = paid.add((BigDecimal) b.get("paid"));
        }
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("academy", acad);
        out.put("bills", bills);
        out.put("toPay", toPay);
        out.put("overdue", overdue);
        out.put("paid", paid);
        out.put("payments", jdbc.queryForList("""
                SELECT p.id, p.paid_on AS "paidOn", p.amount, p.mode, p.reference, i.number, i.period
                FROM invoice_payments p JOIN academy_invoices i ON i.id = p.invoice_id
                WHERE i.academy_id = ? ORDER BY p.paid_on DESC, p.created_at DESC""", academyId));
        out.put("addons", jdbc.queryForList("""
                SELECT d.id, d.name, d.price, d.billing, x.from_period AS "fromPeriod"
                FROM academy_addons x JOIN hq_addons d ON d.id = x.addon_id WHERE x.academy_id = ? ORDER BY d.name""", academyId));
        out.put("reminders", jdbc.queryForList("""
                SELECT r.sent_at AS "sentAt", r.channels, r.message, i.number
                FROM invoice_reminders r JOIN academy_invoices i ON i.id = r.invoice_id
                WHERE i.academy_id = ? ORDER BY r.sent_at DESC LIMIT 6""", academyId));
        return out;
    }

    /**
     * The Overview tab: everything for a month ([month] 'YYYY-MM'), or for a single [day] when given.
     * "Received" is payments by the day they were paid; "billed" is bills by the month (or day) issued.
     */
    @Transactional(readOnly = true)
    public Map<String, Object> overview(String month, String day) {
        LocalDate today = LocalDate.now();
        String ym = month == null || month.isBlank() ? YearMonth.now().toString() : month;
        LocalDate dayDate = day == null || day.isBlank() ? null : LocalDate.parse(day);

        List<Map<String, Object>> all = jdbc.query(BILL_SQL, (rs, i) -> toBill(rs, today));
        List<Map<String, Object>> payments = jdbc.queryForList("""
                SELECT p.id, p.paid_on AS "paidOn", p.amount, p.mode, p.reference, i.number, i.academy_id AS "academyId", a.name AS academy
                FROM invoice_payments p JOIN academy_invoices i ON i.id = p.invoice_id JOIN academies a ON a.id = i.academy_id
                ORDER BY p.paid_on DESC, p.created_at DESC""");

        Map<String, Object> out = new LinkedHashMap<>();
        out.put("month", ym);

        List<Map<String, Object>> inMonth = all.stream().filter(b -> ym.equals(b.get("period")) && !"waived".equals(b.get("status"))).toList();
        List<Map<String, Object>> payMonth = payments.stream().filter(p -> p.get("paidOn").toString().startsWith(ym)).toList();
        List<Map<String, Object>> payDay = dayDate == null ? List.of() : payments.stream().filter(p -> p.get("paidOn").toString().equals(dayDate.toString())).toList();
        List<Map<String, Object>> open = all.stream().filter(b -> ((BigDecimal) b.get("balance")).signum() > 0 && !"waived".equals(b.get("status"))).toList();

        Map<String, Object> kpi = new LinkedHashMap<>();
        kpi.put("received", dayDate == null ? sum(payMonth, "amount") : sum(payDay, "amount"));
        kpi.put("receivedCount", dayDate == null ? payMonth.size() : payDay.size());
        kpi.put("billed", dayDate == null ? sum(inMonth, "total")
                : sum(all.stream().filter(b -> dayDate.equals(b.get("issuedOn"))).toList(), "total"));
        kpi.put("billedCount", dayDate == null ? inMonth.size() : all.stream().filter(b -> dayDate.equals(b.get("issuedOn"))).count());
        List<Map<String, Object>> dueScope = dayDate == null ? inMonth : all;
        kpi.put("due", sum(dueScope.stream().filter(b -> "due".equals(b.get("status"))).toList(), "balance"));
        kpi.put("overdue", sum(dueScope.stream().filter(b -> "overdue".equals(b.get("status"))).toList(), "balance"));
        out.put("kpi", kpi);

        // Received each day of the month, split by how the academy paid.
        YearMonth m = YearMonth.parse(ym);
        int days = ym.equals(YearMonth.now().toString()) ? today.getDayOfMonth() : m.lengthOfMonth();
        Map<String, double[]> byMode = new LinkedHashMap<>();
        for (String mode : MODES) byMode.put(mode, new double[days]);
        for (var p : payMonth) {
            int d = LocalDate.parse(p.get("paidOn").toString()).getDayOfMonth();
            if (d <= days) byMode.computeIfAbsent((String) p.get("mode"), k -> new double[days])[d - 1] += ((BigDecimal) p.get("amount")).doubleValue();
        }
        out.put("days", days);
        out.put("byDay", byMode);

        // Last 6 months: billed, received, unpaid.
        List<Map<String, Object>> trend = new ArrayList<>();
        for (int i = 5; i >= 0; i--) {
            String p = YearMonth.now().minusMonths(i).toString();
            List<Map<String, Object>> bm = all.stream().filter(b -> p.equals(b.get("period")) && !"waived".equals(b.get("status"))).toList();
            Map<String, Object> t = new LinkedHashMap<>();
            t.put("month", p);
            t.put("billed", sum(bm, "total"));
            t.put("received", sum(payments.stream().filter(x -> x.get("paidOn").toString().startsWith(p)).toList(), "amount"));
            t.put("unpaid", sum(bm, "balance"));
            trend.add(t);
        }
        out.put("trend", trend);

        // How late the unpaid bills are.
        String[][] buckets = {{"Not late yet", "blue"}, {"1 to 30 days late", "gold"}, {"31 to 60 days late", "coral"}, {"Over 60 days late", "red"}};
        List<Map<String, Object>> aging = new ArrayList<>();
        for (int k = 0; k < 4; k++) {
            final int kk = k;
            var in = open.stream().filter(b -> {
                long late = (long) b.get("daysLate");
                boolean over = "overdue".equals(b.get("status"));
                return switch (kk) { case 0 -> !over; case 1 -> over && late <= 30; case 2 -> over && late > 30 && late <= 60; default -> over && late > 60; };
            }).toList();
            aging.add(Map.of("label", buckets[k][0], "tone", buckets[k][1], "count", in.size(), "amount", sum(in, "balance")));
        }
        out.put("aging", aging);

        // The academies owing the most past their due date.
        Map<UUID, Map<String, Object>> by = new LinkedHashMap<>();
        for (var b : open) {
            if (!"overdue".equals(b.get("status"))) continue;
            var e = by.computeIfAbsent((UUID) b.get("academyId"), k -> {
                Map<String, Object> x = new LinkedHashMap<>();
                x.put("academyId", k);
                x.put("academy", b.get("academy"));
                x.put("amount", BigDecimal.ZERO);
                x.put("bills", 0);
                x.put("maxLate", 0L);
                return x;
            });
            e.put("amount", ((BigDecimal) e.get("amount")).add((BigDecimal) b.get("balance")));
            e.put("bills", (int) e.get("bills") + 1);
            e.put("maxLate", Math.max((long) e.get("maxLate"), (long) b.get("daysLate")));
        }
        out.put("topOverdue", by.values().stream().sorted(Comparator.comparing((Map<String, Object> e) -> (BigDecimal) e.get("amount")).reversed()).limit(5).toList());
        out.put("overdueAcademies", by.size());
        out.put("overdueTotal", sum(open.stream().filter(b -> "overdue".equals(b.get("status"))).toList(), "balance"));

        // How academies paid in the period.
        Map<String, BigDecimal> modeTotals = new LinkedHashMap<>();
        for (String mode : MODES) modeTotals.put(mode, BigDecimal.ZERO);
        for (var p : dayDate == null ? payMonth : payDay) {
            modeTotals.merge((String) p.get("mode"), (BigDecimal) p.get("amount"), BigDecimal::add);
        }
        out.put("modes", modeTotals);

        // The lists behind the four KPI tiles.
        out.put("payments", dayDate == null ? payMonth : payDay);
        out.put("billedList", dayDate == null ? inMonth : all.stream().filter(b -> dayDate.equals(b.get("issuedOn"))).toList());
        out.put("dueList", dueScope.stream().filter(b -> "due".equals(b.get("status")) && ((BigDecimal) b.get("balance")).signum() > 0).toList());
        out.put("overdueList", dueScope.stream().filter(b -> "overdue".equals(b.get("status"))).toList());

        out.put("reminderSettings", jdbc.queryForMap("SELECT before_3d AS \"b3\", on_due AS \"d0\", after_3d AS \"a3\", weekly AS \"wk\", ch_whatsapp AS \"wa\", ch_email AS \"em\", ch_sms AS \"sm\" FROM hq_reminder_settings WHERE id = 1"));
        out.put("recentReminders", jdbc.queryForList("""
                SELECT a.name AS academy, r.sent_at AS "sentAt", r.channels FROM invoice_reminders r
                JOIN academy_invoices i ON i.id = r.invoice_id JOIN academies a ON a.id = i.academy_id
                ORDER BY r.sent_at DESC LIMIT 4"""));
        out.put("firstPeriod", jdbc.queryForObject("SELECT COALESCE(min(period), to_char(now(), 'YYYY-MM')) FROM academy_invoices", String.class));
        return out;
    }

    private static BigDecimal sum(List<Map<String, Object>> rows, String key) {
        BigDecimal s = BigDecimal.ZERO;
        for (var r : rows) s = s.add((BigDecimal) r.get(key));
        return s;
    }

}
