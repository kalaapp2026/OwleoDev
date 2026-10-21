package com.nest.app.hq.controller;

import com.nest.app.hq.HqAccess;
import com.nest.app.hq.service.HqAcademies;
import com.nest.app.hq.service.HqAlerts;
import com.nest.app.hq.service.HqSeries;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import java.sql.Timestamp;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

@RestController
@Tag(name = "HQ Console")
@PreAuthorize("hasRole('SUPER_ADMIN')")
public class HqOverviewController {

    private final HqAccess access;
    private final HqAcademies academies;
    private final HqSeries series;
    private final HqAlerts alerts;
    private final com.nest.app.hq.service.HqApprovals approvals;
    private final JdbcTemplate jdbc;

    public HqOverviewController(HqAccess access, HqAcademies academies, HqSeries series, HqAlerts alerts, com.nest.app.hq.service.HqApprovals approvals, JdbcTemplate jdbc) {
        this.access = access;
        this.academies = academies;
        this.series = series;
        this.alerts = alerts;
        this.approvals = approvals;
        this.jdbc = jdbc;
    }

    /** The Business tab of the dashboard: KPIs, the 12-month history and who is doing best. */
    @GetMapping("/admin/hq/dashboard")
    public Map<String, Object> dashboard() {
        access.requireModule("overview");
        var rows = academies.all();
        Map<String, Object> out = new LinkedHashMap<>(series.compute());

        long live = rows.stream().filter(r -> r.isOpen()).count();
        int ym = java.time.YearMonth.now().getMonthValue();
        long newThisMonth = rows.stream().filter(r -> java.time.YearMonth.from(r.joined()).equals(java.time.YearMonth.now())).count();
        long churned12 = rows.stream().filter(r -> !r.isOpen()).count();
        long trials = rows.stream().filter(r -> HqAcademies.TRIAL.equals(r.status())).count();

        Map<String, Object> now = new LinkedHashMap<>();
        now.put("activeAcademies", live);
        now.put("newThisMonth", newThisMonth);
        now.put("churned12", churned12);
        now.put("demo", trials);
        now.put("students", rows.stream().filter(r -> r.isOpen()).mapToInt(HqAcademies.Row::students).sum());
        now.put("trainers", rows.stream().filter(r -> r.isOpen()).mapToInt(HqAcademies.Row::trainers).sum());
        now.put("alerts", alerts.all().size());
        now.put("month", ym);
        out.put("now", now);

        // Money belongs to the Finance workspace; the business dashboard shows people and health only.
        for (String k : List.of("mrr", "revenue", "expenses", "profit", "streams", "expenseLines")) {
            out.remove(k);
        }

        // Academy health across live academies: Healthy >= 80, Watch 62-79, At risk < 62.
        var liveRows = rows.stream().filter(r -> HqAcademies.LIVE.equals(r.status())).toList();
        Map<String, Object> hm = new LinkedHashMap<>();
        hm.put("healthy", liveRows.stream().filter(r -> r.health() >= 80).count());
        hm.put("watch", liveRows.stream().filter(r -> r.health() >= 62 && r.health() < 80).count());
        hm.put("atRisk", liveRows.stream().filter(r -> r.health() < 62).count());
        hm.put("average", liveRows.isEmpty() ? 0 : (int) Math.round(liveRows.stream().mapToInt(HqAcademies.Row::health).average().orElse(0)));
        out.put("healthMix", hm);

        // Plan mix across paying academies.
        Map<String, Map<String, Object>> mix = new LinkedHashMap<>();
        for (var r : rows) {
            if (!r.isPaying()) {
                continue;
            }
            var m = mix.computeIfAbsent(r.plan(), k -> {
                Map<String, Object> e = new LinkedHashMap<>();
                e.put("plan", r.plan());
                e.put("name", r.planName());
                e.put("price", r.planPrice());
                e.put("count", 0);
                return e;
            });
            m.put("count", (int) m.get("count") + 1);
        }
        addPlanTones(mix);
        out.put("planMix", new ArrayList<>(mix.values()));

        out.put("top", rows.stream().filter(r -> HqAcademies.LIVE.equals(r.status()))
                .sorted(HqAcademies.byHealthDesc()).limit(6).toList());
        out.put("activity", activity());
        return out;
    }

    @GetMapping("/admin/hq/alerts")
    public List<HqAlerts.Alert> alerts() {
        access.requireModule("alerts");
        return alerts.all();
    }

    /** The red counts on the dock and More tiles: how many things are waiting in each module. */
    @GetMapping("/admin/hq/badges")
    public Map<String, Long> badges() {
        Map<String, Long> b = new LinkedHashMap<>();
        var al = alerts.all();
        b.put("alerts", (long) al.size());
        b.put("collections", al.stream().filter(a -> "payment".equals(a.kind())).count());
        b.put("artists", count("SELECT count(*) FROM artist_applications WHERE status = 'PENDING'"));
        var ac = approvals.counts();
        b.put("approvals", ac.get("escalated") + ac.get("delayed"));
        b.put("events", count("SELECT count(*) FROM events WHERE event_date::date = current_date"));
        return b;
    }

    private long count(String sql) {
        Long n = jdbc.queryForObject(sql, Long.class);
        return n == null ? 0 : n;
    }

    /** Newest things that happened across the platform: payments, new academies, HQ actions. */
    private List<Map<String, Object>> activity() {
        List<Map<String, Object>> items = new ArrayList<>();
        jdbc.query("""
                SELECT a.name, p.amount, p.created_at FROM invoice_payments p
                JOIN academy_invoices i ON i.id = p.invoice_id JOIN academies a ON a.id = i.academy_id
                ORDER BY p.created_at DESC LIMIT 5""", rs -> {
            items.add(item(rs.getString("name"), "paid " + inrOf(rs.getBigDecimal("amount")), "green", "check", rs.getTimestamp("created_at")));
        });
        jdbc.query("SELECT name, created_at, demo_ends_on FROM academies ORDER BY created_at DESC LIMIT 5", rs -> {
            boolean demo = rs.getObject("demo_ends_on") != null;
            items.add(item(rs.getString("name"), demo ? "started a demo" : "joined Owleo", demo ? "blue" : "primary",
                    demo ? "clock" : "rocket", rs.getTimestamp("created_at")));
        });
        jdbc.query("SELECT actor_name, detail, occurred_at FROM hq_audit_log ORDER BY occurred_at DESC LIMIT 5", rs -> {
            items.add(item(rs.getString("actor_name"), rs.getString("detail"), "violet", "flow", rs.getTimestamp("occurred_at")));
        });
        items.sort(Comparator.comparing((Map<String, Object> m) -> (Timestamp) m.get("at")).reversed());
        return items.stream().limit(6).map(m -> {
            m.put("at", ((Timestamp) m.get("at")).toInstant());
            return m;
        }).toList();
    }

    private static Map<String, Object> item(String who, String text, String tone, String icon, Timestamp at) {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("who", who);
        m.put("text", text);
        m.put("tone", tone);
        m.put("icon", icon);
        m.put("at", at);
        return m;
    }

    private static String inrOf(java.math.BigDecimal v) {
        return "₹" + java.text.NumberFormat.getIntegerInstance(new java.util.Locale("en", "IN")).format(v.setScale(0, java.math.RoundingMode.HALF_UP));
    }

    private void addPlanTones(Map<String, Map<String, Object>> mix) {
        jdbc.query("SELECT code, tone FROM billing_plans", rs -> {
            var m = mix.get(rs.getString("code"));
            if (m != null) {
                m.put("tone", rs.getString("tone"));
            }
        });
    }
}
