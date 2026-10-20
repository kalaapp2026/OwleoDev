package com.nest.app.hq.service;

import com.nest.app.hq.HqAccess;
import com.nest.app.hq.HqAudit;
import com.nest.app.hq.HqRole;
import com.nest.common.exception.BadRequestException;
import com.nest.common.exception.ForbiddenException;
import com.nest.common.exception.ResourceNotFoundException;
import com.nest.common.security.TenantContext;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

/**
 * Support tickets. Super, Operations and Support admins see everything; a Finance admin sees student
 * fee problems only. Anyone who can open Support may reply; only a reply moves a ticket on.
 */
@Service
public class HqSupport {

    public static final Map<String, List<String>> CATEGORIES = Map.of(
            "ISSUE", List.of("Login and access", "Payments and payouts", "Data and sync", "App bug", "Billing"),
            "ENQUIRY", List.of("Plan and pricing", "Feature request", "Onboarding", "Integration"),
            "FEEDBACK", List.of("Product", "Reports", "Support"),
            "FEE", List.of("Charged twice", "Paid but shows unpaid", "Refund request", "Receipt or invoice", "Instalment request"));

    private final JdbcTemplate jdbc;
    private final HqAudit audit;
    private final HqAccess access;

    public HqSupport(JdbcTemplate jdbc, HqAudit audit, HqAccess access) {
        this.jdbc = jdbc;
        this.audit = audit;
        this.access = access;
    }

    private Set<String> visibleKinds() {
        return access.role() == HqRole.FINANCE ? Set.of("FEE") : Set.of("ISSUE", "ENQUIRY", "FEEDBACK", "FEE");
    }

    private static String ref(long seq) {
        return "T-" + (2040 + seq);
    }

    private static boolean open(String status) {
        return !"RESOLVED".equals(status) && !"CLOSED".equals(status);
    }

    private static final String ROWS = """
            SELECT t.id, t.seq, t.kind, t.academy_id, a.name AS academy, t.category, t.priority, t.status, t.raised_by, t.raised_role,
                   t.subject, t.body, t.rating, t.amount, t.assignee, t.created_at,
                   GREATEST(0, (current_date - t.created_at::date)) AS age
            FROM hq_tickets t LEFT JOIN academies a ON a.id = t.academy_id""";

    private Map<String, Object> card(Map<String, Object> r) {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("id", r.get("id"));
        m.put("ref", ref(((Number) r.get("seq")).longValue()));
        m.put("kind", ((String) r.get("kind")).toLowerCase());
        m.put("academyId", r.get("academy_id"));
        m.put("academy", r.get("academy"));
        m.put("category", r.get("category"));
        m.put("priority", ((String) r.get("priority")).toLowerCase());
        m.put("status", ((String) r.get("status")).toLowerCase());
        m.put("from", r.get("raised_by"));
        m.put("role", r.get("raised_role"));
        m.put("subject", r.get("subject"));
        m.put("rating", r.get("rating"));
        m.put("age", r.get("age"));
        return m;
    }

    public Map<String, Object> list(String kind, String st, String q) {
        Set<String> kinds = visibleKinds();
        var rows = jdbc.queryForList(ROWS + " ORDER BY t.created_at DESC").stream().filter(r -> kinds.contains((String) r.get("kind"))).toList();
        int open = 0, high = 0, waiting = 0, resolved = 0, rated = 0, stars = 0;
        Map<String, Integer> byKind = new LinkedHashMap<>();
        for (String k : List.of("issue", "enquiry", "feedback", "fee")) byKind.put(k, 0);
        List<Map<String, Object>> items = new ArrayList<>();
        String needle = q == null ? "" : q.trim().toLowerCase();
        for (var r : rows) {
            String status = (String) r.get("status");
            boolean isOpen = open(status);
            String k = ((String) r.get("kind")).toLowerCase();
            if (isOpen) {
                open++;
                byKind.merge(k, 1, Integer::sum);
                if ("URGENT".equals(r.get("priority")) || "HIGH".equals(r.get("priority"))) high++;
                if ("WAITING".equals(status)) waiting++;
            }
            if ("RESOLVED".equals(status)) resolved++;
            if (r.get("rating") != null) {
                rated++;
                stars += ((Number) r.get("rating")).intValue();
            }
            Map<String, Object> c = card(r);
            if (kind != null && !kind.isBlank() && !"all".equals(kind) && !kind.equals(c.get("kind"))) continue;
            if ("open".equals(st) && !isOpen) continue;
            if ("done".equals(st) && isOpen) continue;
            if (!needle.isEmpty() && !(r.get("subject") + " " + r.get("raised_by") + " " + r.get("academy") + " " + c.get("ref")).toLowerCase().contains(needle)) continue;
            items.add(c);
        }
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("items", items);
        out.put("open", open);
        out.put("high", high);
        out.put("waiting", waiting);
        out.put("resolved", resolved);
        out.put("rated", rated);
        out.put("rating", rated == 0 ? null : Math.round(stars * 10.0 / rated) / 10.0);
        out.put("byKind", byKind);
        out.put("kinds", visibleKinds().stream().map(String::toLowerCase).sorted().toList());
        out.put("categories", CATEGORIES.entrySet().stream().collect(java.util.stream.Collectors.toMap(e -> e.getKey().toLowerCase(), Map.Entry::getValue)));
        out.put("academies", jdbc.queryForList("SELECT id, name FROM academies WHERE closed_at IS NULL ORDER BY name"));
        return out;
    }

    public Map<String, Object> counts() {
        Map<String, Object> l = list("all", "open", null);
        return Map.of("open", l.get("open"), "high", l.get("high"), "rating", l.get("rating") == null ? "–" : l.get("rating"));
    }

    private Map<String, Object> row(UUID id) {
        var rows = jdbc.queryForList(ROWS + " WHERE t.id = ?", id);
        if (rows.isEmpty() || !visibleKinds().contains((String) rows.get(0).get("kind"))) throw new ResourceNotFoundException("Ticket not found");
        return rows.get(0);
    }

    public Map<String, Object> detail(UUID id) {
        var r = row(id);
        Map<String, Object> m = card(r);
        m.put("body", r.get("body"));
        m.put("amount", r.get("amount"));
        m.put("assignee", r.get("assignee"));
        m.put("thread", jdbc.queryForList("SELECT author AS who, from_hq AS \"hq\", body AS x, at FROM hq_ticket_messages WHERE ticket_id = ? ORDER BY at", id));
        return m;
    }

    private String actorName() {
        UUID actor = TenantContext.currentUserIdOrNull();
        var n = actor == null ? List.<String>of() : jdbc.queryForList("SELECT full_name FROM users WHERE id = ?", String.class, actor);
        return n.isEmpty() ? "Support team" : n.get(0);
    }

    @Transactional
    public void reply(UUID id, String message, String status, String priority) {
        var r = row(id);
        String msg = message == null ? "" : message.trim();
        String st = status == null || status.isBlank() ? ((String) r.get("status")).toLowerCase() : status.toLowerCase();
        String pr = priority == null || priority.isBlank() ? ((String) r.get("priority")).toLowerCase() : priority.toLowerCase();
        if (!Set.of("open", "progress", "waiting", "resolved", "closed").contains(st)) throw new BadRequestException("Unknown status.");
        if (!Set.of("urgent", "high", "medium", "low").contains(pr)) throw new BadRequestException("Unknown priority.");
        boolean statusChanged = !st.equalsIgnoreCase((String) r.get("status"));
        boolean prChanged = !pr.equalsIgnoreCase((String) r.get("priority"));
        if (msg.isEmpty() && !statusChanged && !prChanged) throw new BadRequestException("Write a reply or change the status.");
        if (msg.length() > 2000) throw new BadRequestException("Keep the reply under 2000 characters.");
        String who = actorName();
        if (!msg.isEmpty()) jdbc.update("INSERT INTO hq_ticket_messages (ticket_id, author, from_hq, body) VALUES (?, ?, TRUE, ?)", id, who, msg);
        if (statusChanged) {
            jdbc.update("INSERT INTO hq_ticket_messages (ticket_id, author, from_hq, body) VALUES (?, 'System', FALSE, ?)", id, "Status changed to " + label(st));
        }
        jdbc.update("""
                UPDATE hq_tickets SET status = ?, priority = ?, assignee = COALESCE(assignee, ?),
                       resolved_at = CASE WHEN ? THEN COALESCE(resolved_at, now()) ELSE NULL END WHERE id = ?""",
                st.toUpperCase(), pr.toUpperCase(), who, "resolved".equals(st) || "closed".equals(st), id);
        audit.log("support", (UUID) r.get("academy_id"), "Replied on " + ref(((Number) r.get("seq")).longValue()) + ("resolved".equals(st) ? " and resolved it" : ""));
    }

    private static String label(String st) {
        return switch (st) { case "progress" -> "In progress"; case "waiting" -> "Waiting on academy"; default -> Character.toUpperCase(st.charAt(0)) + st.substring(1); };
    }

    @Transactional
    public void escalate(UUID id) {
        var r = row(id);
        jdbc.update("UPDATE hq_tickets SET priority = 'URGENT' WHERE id = ?", id);
        jdbc.update("INSERT INTO hq_ticket_messages (ticket_id, author, from_hq, body) VALUES (?, ?, TRUE, 'Escalated to urgent.')", id, actorName());
        audit.log("support", (UUID) r.get("academy_id"), "Escalated " + ref(((Number) r.get("seq")).longValue()) + " to urgent");
    }

    @Transactional
    public void review(UUID id) {
        var r = row(id);
        if (!"FEEDBACK".equals(r.get("kind"))) throw new BadRequestException("Only feedback is marked as reviewed.");
        jdbc.update("UPDATE hq_tickets SET status = 'CLOSED', resolved_at = COALESCE(resolved_at, now()) WHERE id = ?", id);
        audit.log("support", (UUID) r.get("academy_id"), "Reviewed feedback " + ref(((Number) r.get("seq")).longValue()));
    }

    @Transactional
    public UUID create(Map<String, Object> b) {
        String kind = str(b, "kind").toUpperCase(), cat = str(b, "category"), from = str(b, "from"), subj = str(b, "subject"), body = str(b, "body");
        if (!visibleKinds().contains(kind)) throw new ForbiddenException("This role cannot log that kind of ticket.");
        if (!CATEGORIES.get(kind).contains(cat)) throw new BadRequestException("Choose a category.");
        if (from.length() < 2) throw new BadRequestException("Enter who raised it.");
        if (subj.length() < 4) throw new BadRequestException("Add a short subject.");
        if (body.length() < 5) throw new BadRequestException("Add a few details.");
        UUID academy = null;
        if (!str(b, "academy").isEmpty()) {
            academy = UUID.fromString(str(b, "academy"));
            if (jdbc.queryForObject("SELECT count(*) FROM academies WHERE id = ?", Integer.class, academy) == 0) throw new BadRequestException("Choose an academy.");
        }
        UUID id = UUID.randomUUID();
        BigDecimal amount = "FEE".equals(kind) && b.get("amount") != null && !b.get("amount").toString().isBlank() ? new BigDecimal(b.get("amount").toString()) : null;
        jdbc.update("""
                INSERT INTO hq_tickets (id, kind, academy_id, category, raised_by, raised_role, subject, body, amount)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)""", id, kind, academy, cat, from, "FEE".equals(kind) ? "Student" : "Academy admin", subj, body, amount);
        jdbc.update("INSERT INTO hq_ticket_messages (ticket_id, author, from_hq, body) VALUES (?, ?, FALSE, ?)", id, from, body);
        audit.log("support", academy, "Logged ticket " + subj);
        return id;
    }

    /** Rows for the tickets report, honouring the role's visibility. */
    public List<Map<String, Object>> export(UUID academy) {
        Set<String> kinds = visibleKinds();
        List<Map<String, Object>> out = new ArrayList<>();
        for (var r : jdbc.queryForList(ROWS + " ORDER BY t.created_at DESC")) {
            if (!kinds.contains((String) r.get("kind"))) continue;
            if (academy != null && !academy.equals(r.get("academy_id"))) continue;
            Map<String, Object> c = card(r);
            c.put("kind", ((String) r.get("kind")).charAt(0) + ((String) r.get("kind")).substring(1).toLowerCase());
            c.put("status", label((String) c.get("status")));
            out.add(c);
        }
        return out;
    }

    private static String str(Map<String, Object> b, String k) {
        Object v = b.get(k);
        return v == null ? "" : v.toString().trim();
    }
}
