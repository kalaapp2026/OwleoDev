package com.nest.app.hq.controller;

import com.nest.app.hq.HqAccess;
import com.nest.app.hq.HqAudit;
import com.nest.app.hq.service.HqAcademies;
import com.nest.app.hq.service.HqSeries;
import com.nest.common.exception.BadRequestException;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/** The two analysis pages on the Business side: Growth (against targets) and Finance (profit and loss). */
@RestController
@Tag(name = "HQ Console")
@PreAuthorize("hasRole('SUPER_ADMIN')")
public class HqInsightsController {


    private final HqAccess access;
    private final HqAcademies academies;
    private final HqSeries series;
    private final HqAudit audit;
    private final JdbcTemplate jdbc;

    public HqInsightsController(HqAccess access, HqAcademies academies, HqSeries series, HqAudit audit, JdbcTemplate jdbc) {
        this.access = access;
        this.academies = academies;
        this.series = series;
        this.audit = audit;
        this.jdbc = jdbc;
    }

    @GetMapping("/admin/hq/growth")
    public Map<String, Object> growth() {
        access.requireModule("growth");
        Map<String, Object> out = new LinkedHashMap<>(series.compute());
        var rows = academies.all();
        var open = rows.stream().filter(HqAcademies.Row::isOpen).toList();

        Map<String, long[]> byCity = new LinkedHashMap<>();
        for (var a : open) {
            long[] v = byCity.computeIfAbsent(a.city() == null ? "Unknown" : a.city(), k -> new long[2]);
            v[0]++;
            v[1] += a.users();
        }
        out.put("cities", byCity.entrySet().stream()
                .sorted((x, y) -> Long.compare(y.getValue()[1], x.getValue()[1])).limit(6)
                .map(e -> Map.<String, Object>of("city", e.getKey(), "academies", e.getValue()[0], "users", e.getValue()[1])).toList());

        Map<String, long[]> byType = new LinkedHashMap<>();
        for (String t : new String[]{"Dance", "Music", "Fine Arts", "Theatre", "Multi"}) {
            byType.put(t, new long[2]);
        }
        for (var a : open) {
            long[] v = byType.computeIfAbsent(a.type(), k -> new long[2]);
            v[0]++;
            v[1] += a.users();
        }
        out.put("types", byType.entrySet().stream()
                .map(e -> Map.<String, Object>of("type", e.getKey(), "academies", e.getValue()[0], "users", e.getValue()[1])).toList());

        long lost = rows.stream().filter(r -> !r.isOpen()).count();
        double[] mrr = (double[]) out.get("mrr");
        long[] users = (long[]) out.get("users");
        long[] paying = (long[]) out.get("paying");
        int cur = mrr.length - 1;
        Map<String, Object> q = new LinkedHashMap<>();
        q.put("retention", rows.isEmpty() ? 100 : Math.round((1 - (double) lost / rows.size()) * 100));
        q.put("lost", lost);
        q.put("total", rows.size());
        q.put("usersPerAcademy", open.isEmpty() ? 0 : Math.round((double) users[cur] / open.size()));
        q.put("arpa", paying[cur] == 0 ? 0 : Math.round(mrr[cur] / paying[cur]));
        q.put("revenuePerUser", users[cur] == 0 ? 0 : Math.round(mrr[cur] / users[cur]));
        out.put("quality", q);

        List<Map<String, Object>> targets = new ArrayList<>();
        jdbc.query("SELECT key, label, target FROM hq_targets ORDER BY CASE key WHEN 'academies' THEN 1 WHEN 'users' THEN 2 WHEN 'mrr' THEN 3 ELSE 4 END", rs -> {
            String key = rs.getString("key");
            Map<String, Object> t = new LinkedHashMap<>();
            t.put("key", key);
            t.put("label", rs.getString("label"));
            t.put("target", rs.getBigDecimal("target"));
            t.put("series", out.get(switch (key) {
                case "academies" -> "academies";
                case "users" -> "users";
                case "mrr" -> "mrr";
                default -> "revenue";
            }));
            targets.add(t);
        });
        out.put("targets", targets);
        return out;
    }

    @PutMapping("/admin/hq/growth/targets/{key}")
    @Transactional
    public void setTarget(@PathVariable String key, @RequestBody Map<String, Object> body) {
        access.requireModule("growth");
        access.requireSuper();
        BigDecimal t;
        try {
            t = new BigDecimal(String.valueOf(body.get("target")));
        } catch (NumberFormatException e) {
            throw new BadRequestException("Enter the target as a number.");
        }
        if (t.signum() <= 0) throw new BadRequestException("The target must be above zero.");
        int n = jdbc.update("UPDATE hq_targets SET target = ? WHERE key = ?", t, key);
        if (n == 0) throw new BadRequestException("Unknown target: " + key);
        audit.log("growth", "Set the " + key + " target to " + t.toBigInteger());
    }

    @GetMapping("/admin/hq/finance")
    public Map<String, Object> finance() {
        access.requireModule("finance");
        access.requireFinanceWorkspace();
        Map<String, Object> out = new LinkedHashMap<>(series.compute());
        List<Map<String, Object>> overdue = new ArrayList<>();
        jdbc.query("""
                SELECT a.name, SUM(i.total - COALESCE((SELECT SUM(p.amount) FROM invoice_payments p WHERE p.invoice_id = i.id), 0)) AS bal
                FROM academy_invoices i JOIN academies a ON a.id = i.academy_id
                WHERE i.status = 'DUE' AND i.due_on < current_date GROUP BY a.name ORDER BY bal DESC""", rs -> {
            overdue.add(Map.of("name", rs.getString("name"), "amount", rs.getBigDecimal("bal")));
        });
        out.put("overdue", overdue);
        out.put("canEdit", access.role().name().equals("SUPER") || access.role().name().equals("FINANCE"));
        return out;
    }

}
