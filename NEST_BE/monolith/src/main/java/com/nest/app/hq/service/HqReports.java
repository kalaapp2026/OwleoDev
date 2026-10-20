package com.nest.app.hq.service;

import com.nest.app.hq.HqAudit;
import com.nest.common.exception.BadRequestException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

import java.sql.Timestamp;
import java.time.YearMonth;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

/**
 * The reports gallery: each report is a header and rows the console turns into a CSV. Rows are read
 * live, so the count on a card is exactly what an export would contain. Only authorised roles may
 * export, and every export leaves an audit line.
 */
@Service
public class HqReports {

    private record Def(String key, String name, String description, String icon, String tone) {
    }

    private static final List<Def> DEFS = List.of(
            new Def("users", "User master", "Profiles, mapping and missing data", "users", "blue"),
            new Def("entities", "Entities", "Academies, plans and health", "bld", "primary"),
            new Def("payments", "Payments", "Platform fees and their status", "wallet", "gold"),
            new Def("approvals", "Approvals", "Requests and their outcomes", "flow", "violet"),
            new Def("courses", "Courses", "Courses across academies", "book", "green"),
            new Def("batches", "Batches", "Capacity, trainers and issues", "layers", "coral"),
            new Def("exits", "Exits", "Offboarding and access removal", "exit", "magenta"),
            new Def("tickets", "Support tickets", "Issues, enquiries, feedback and fee tickets", "msg", "blue"));

    private final JdbcTemplate jdbc;
    private final HqAudit audit;
    private final HqUsers users;
    private final HqAcademies academies;
    private final HqCollections collections;
    private final HqCourses courses;
    private final HqExits exits;
    private final HqSupport support;

    public HqReports(JdbcTemplate jdbc, HqAudit audit, HqUsers users, HqAcademies academies, HqCollections collections, HqCourses courses,
                     HqExits exits, HqSupport support) {
        this.jdbc = jdbc;
        this.audit = audit;
        this.users = users;
        this.academies = academies;
        this.collections = collections;
        this.courses = courses;
        this.exits = exits;
        this.support = support;
    }

    public Map<String, Object> summary(UUID academy, int months) {
        List<Map<String, Object>> reports = new ArrayList<>();
        for (Def d : DEFS) {
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("key", d.key());
            m.put("name", d.name());
            m.put("description", d.description());
            m.put("icon", d.icon());
            m.put("tone", d.tone());
            m.put("rows", ((List<?>) build(d.key(), academy, months).get("rows")).size());
            reports.add(m);
        }
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("reports", reports);
        out.put("academies", jdbc.queryForList("SELECT id, name FROM academies WHERE closed_at IS NULL ORDER BY name"));
        out.put("audit", audit.recent(null, null, 12));
        return out;
    }

    /** The report as headers and rows. With [export] it checks the role and writes the audit line. */
    public Map<String, Object> data(String key, UUID academy, int months, boolean export) {
        Map<String, Object> out = build(key, academy, months);
        if (export) {
            Def d = DEFS.stream().filter(x -> x.key().equals(key)).findFirst().orElseThrow();
            audit.log("reports", "Exported " + d.name() + " (" + ((List<?>) out.get("rows")).size() + " rows)");
        }
        return out;
    }

    private Map<String, Object> build(String key, UUID academy, int months) {
        List<String> head;
        List<List<Object>> rows = new ArrayList<>();
        Timestamp since = Timestamp.valueOf(YearMonth.now().minusMonths(Math.max(0, months - 1)).atDay(1).atStartOfDay());
        switch (key) {
            case "users" -> {
                head = List.of("ID", "Name", "Role", "Academy", "Course", "Status", "Missing fields");
                for (var u : users.listAll(academy)) {
                    rows.add(List.of(u.get("ref"), u.get("name"), u.get("role"), u.get("academy"), nz(u.get("course")), u.get("status"), u.get("missing")));
                }
            }
            case "entities" -> {
                head = List.of("Academy", "City", "Type", "Plan", "Status", "Students", "Trainers", "Health");
                for (var a : academies.all()) {
                    if (academy != null && !academy.equals(a.id())) continue;
                    rows.add(List.of(a.name(), nz(a.city()), nz(a.type()), nz(a.planName()), a.status(), a.students(), a.trainers(), a.health()));
                }
            }
            case "payments" -> {
                head = List.of("Bill", "Academy", "Period", "Plan", "Total", "Paid", "Balance", "Status");
                YearMonth from = YearMonth.now().minusMonths(Math.max(0, months - 1));
                for (YearMonth p = YearMonth.now(); !p.isBefore(from); p = p.minusMonths(1)) {
                    for (var b : collections.bills(p.toString(), academy == null ? null : academy.toString())) {
                        rows.add(List.of(nz(b.get("number")), nz(b.get("academy")), nz(b.get("period")), nz(b.get("planName")), nz(b.get("total")), nz(b.get("paid")), nz(b.get("balance")), nz(b.get("status"))));
                    }
                }
            }
            case "approvals" -> {
                head = List.of("Request", "Type", "Academy", "Status", "Waiting days");
                for (var r : jdbc.queryForList("""
                        SELECT 'R-' || (1000 + r.seq) AS number, w.label, COALESCE(a.name, 'Owleo HQ') AS academy,
                               CASE WHEN r.decision IS NOT NULL THEN r.decision ELSE 'pending' END AS status,
                               GREATEST(0, (COALESCE(r.decided_at, now())::date - r.created_at::date)) AS days
                        FROM hq_requests r JOIN hq_workflows w ON w.type = r.type LEFT JOIN academies a ON a.id = r.academy_id
                        WHERE r.created_at >= ? AND (?::uuid IS NULL OR r.academy_id = ?::uuid) ORDER BY r.seq DESC""", since, academy, academy)) {
                    rows.add(List.of(r.get("number"), r.get("label"), r.get("academy"), r.get("status"), r.get("days")));
                }
            }
            case "courses" -> {
                head = List.of("Course", "Academies", "Batches", "Enrolled");
                Map<String, int[]> agg = new LinkedHashMap<>();
                Map<String, java.util.Set<Object>> acad = new LinkedHashMap<>();
                for (var b : items(courses.list(academy, null, null, null))) {
                    String c = (String) b.get("course");
                    int[] v = agg.computeIfAbsent(c, k -> new int[2]);
                    v[0]++;
                    v[1] += ((Number) b.get("enrolled")).intValue();
                    acad.computeIfAbsent(c, k -> new java.util.HashSet<>()).add(b.get("academyId"));
                }
                agg.forEach((c, v) -> rows.add(List.of(c, acad.get(c).size(), v[0], v[1])));
            }
            case "batches" -> {
                head = List.of("Academy", "Course", "Batch", "Trainer", "Status", "Enrolled", "Issues");
                for (var b : items(courses.list(academy, null, null, null))) {
                    rows.add(List.of(b.get("academy"), b.get("course"), b.get("batch"), b.get("trainer") == null ? "None" : b.get("trainer"), b.get("status"), b.get("enrolled"),
                            String.join("; ", ((List<?>) b.get("flags")).stream().map(Object::toString).toList())));
                }
            }
            case "exits" -> {
                head = List.of("Exit", "Person", "Academy scope", "Reason", "Effective", "Status");
                for (var x : items(exits.list())) {
                    if (academy != null && !academy.equals(x.get("homeId"))) continue;
                    rows.add(List.of(x.get("ref"), x.get("name"), x.get("scope") == null ? "All" : x.get("scope"), x.get("reason"), String.valueOf(x.get("effective")), x.get("state")));
                }
            }
            case "tickets" -> {
                head = List.of("Ticket", "Type", "Academy", "Category", "Priority", "Status", "Raised by");
                for (var t : support.export(academy)) {
                    rows.add(List.of(t.get("ref"), t.get("kind"), nz(t.get("academy")), nz(t.get("category")), t.get("priority"), t.get("status"), nz(t.get("from"))));
                }
            }
            default -> throw new BadRequestException("Unknown report.");
        }
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("headers", head);
        out.put("rows", rows);
        return out;
    }

    @SuppressWarnings("unchecked")
    private static List<Map<String, Object>> items(Map<String, Object> m) {
        return (List<Map<String, Object>>) m.get("items");
    }

    private static Object nz(Object o) {
        return o == null ? "" : o;
    }
}
