package com.nest.app.hq.service;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.nest.app.hq.HqAccess;
import com.nest.app.hq.HqAudit;
import com.nest.app.hq.HqRole;
import com.nest.common.exception.BadRequestException;
import com.nest.common.exception.ConflictException;
import com.nest.common.exception.ForbiddenException;
import com.nest.common.exception.ResourceNotFoundException;
import com.nest.common.security.TenantContext;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.sql.Timestamp;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.stream.Collectors;

/**
 * Requests that wait for an HQ decision, and the flow each one follows. A request moves through
 * the stages of its kind's workflow (one HQ approver, or an owner then Operations); the last
 * approval applies its effect, and a rejection or return ends it with the reason recorded.
 *
 * <p>Its age is counted from when it reached the current stage: past the workflow's time limit it
 * is DELAYED, past twice that it is ESCALATED. Those are labels that tell the owner what to chase;
 * nothing changes hands automatically.
 */
@Service
public class HqApprovals {

    /** Published after every final decision so the module a request belongs to (onboarding, exits) can react. */
    public record RequestDecided(UUID id, String type, String decision, String refKind, String refId, UUID academyId, String comment) {
    }

    private final JdbcTemplate jdbc;
    private final HqAudit audit;
    private final HqAccess access;
    private final ObjectMapper json;
    private final ApplicationEventPublisher events;
    private final HqAcademyService academyService;

    public HqApprovals(JdbcTemplate jdbc, HqAudit audit, HqAccess access, ObjectMapper json, ApplicationEventPublisher events,
                       HqAcademyService academyService) {
        this.jdbc = jdbc;
        this.audit = audit;
        this.access = access;
        this.json = json;
        this.events = events;
        this.academyService = academyService;
    }

    // ---------------------------------------------------------------- reading

    /** Every request, newest first, with its stage, status and history. */
    @Transactional
    public List<Map<String, Object>> list() {
        syncAcademyRequests();
        HqRole role = access.role();
        Map<String, Map<String, Object>> workflows = workflows().stream().collect(Collectors.toMap(w -> (String) w.get("type"), w -> w));

        Map<UUID, List<Map<String, Object>>> history = new HashMap<>();
        jdbc.query("SELECT request_id, at, who, text FROM hq_request_history ORDER BY at DESC", rs -> {
            Map<String, Object> h = new LinkedHashMap<>();
            h.put("at", rs.getTimestamp("at").toInstant());
            h.put("who", rs.getString("who"));
            h.put("text", rs.getString("text"));
            history.computeIfAbsent(rs.getObject("request_id", UUID.class), k -> new ArrayList<>()).add(h);
        });

        Instant now = Instant.now();
        return jdbc.query("""
                SELECT r.id, 'R-' || (1000 + r.seq) AS number, r.type, r.academy_id, a.name AS academy, r.requested_by, r.summary,
                       r.details, r.payload, r.stage, r.stage_since, r.created_at, r.decision, r.ref_kind, r.ref_id, r.source_id
                FROM hq_requests r LEFT JOIN academies a ON a.id = r.academy_id ORDER BY r.created_at DESC""", (rs, i) -> {
            String type = rs.getString("type");
            var w = workflows.get(type);
            @SuppressWarnings("unchecked") List<String> stages = (List<String>) w.get("stages");
            int stage = Math.min(rs.getInt("stage"), stages.size() - 1);
            String decision = rs.getString("decision");
            int sla = (int) w.get("slaDays");
            long age = ChronoUnit.DAYS.between(rs.getTimestamp("stage_since").toInstant(), now);
            String status = decision != null ? decision : age > sla * 2L ? "escalated" : age > sla ? "delayed" : "pending";
            String stageRole = stages.get(stage);
            Map<String, Object> m = new LinkedHashMap<>();
            UUID id = rs.getObject("id", UUID.class);
            m.put("id", id);
            m.put("number", rs.getString("number"));
            m.put("type", type);
            m.put("typeLabel", w.get("label"));
            m.put("academyId", rs.getObject("academy_id"));
            m.put("academy", rs.getString("academy"));
            m.put("requestedBy", rs.getString("requested_by"));
            m.put("summary", rs.getString("summary"));
            m.put("details", read(rs.getString("details"), new TypeReference<List<List<String>>>() { }));
            m.put("payload", read(rs.getString("payload"), new TypeReference<Map<String, Object>>() { }));
            m.put("stage", stage);
            m.put("stages", stages);
            m.put("stageRole", stageRole);
            m.put("status", status);
            m.put("ageDays", age);
            m.put("slaDays", sla);
            m.put("createdAt", rs.getTimestamp("created_at").toInstant());
            m.put("canAct", decision == null && canAct(role, stageRole));
            m.put("refKind", rs.getString("ref_kind"));
            m.put("refId", rs.getString("ref_id"));
            m.put("fromAcademyApp", rs.getObject("source_id") != null);
            m.put("history", history.getOrDefault(id, List.of()));
            return m;
        });
    }

    @Transactional
    public Map<String, Long> counts() {
        long pending = 0, delayed = 0, escalated = 0, decided = 0;
        for (var r : list()) {
            switch ((String) r.get("status")) {
                case "pending" -> pending++;
                case "delayed" -> delayed++;
                case "escalated" -> escalated++;
                default -> decided++;
            }
        }
        Map<String, Long> out = new LinkedHashMap<>();
        out.put("pending", pending);
        out.put("delayed", delayed);
        out.put("escalated", escalated);
        out.put("decided", decided);
        return out;
    }

    static boolean canAct(HqRole role, String stageRole) {
        return role == HqRole.SUPER
                || (role == HqRole.OPS && "Operations admin".equals(stageRole))
                || (role == HqRole.FINANCE && "Finance admin".equals(stageRole));
    }

    // ---------------------------------------------------------------- workflows

    @Transactional(readOnly = true)
    public List<Map<String, Object>> workflows() {
        return jdbc.query("SELECT type, label, stages, sla_days, escalate_to, locked FROM hq_workflows ORDER BY sort_order", (rs, i) -> {
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("type", rs.getString("type"));
            m.put("label", rs.getString("label"));
            m.put("stages", Arrays.asList(rs.getString("stages").split(",")));
            m.put("slaDays", rs.getInt("sla_days"));
            m.put("escalateTo", rs.getString("escalate_to"));
            m.put("locked", rs.getBoolean("locked"));
            return m;
        });
    }

    @Transactional
    public void saveWorkflow(String type, Integer slaDays, Boolean locked) {
        access.requireSuper();
        var w = workflows().stream().filter(x -> x.get("type").equals(type)).findFirst().orElseThrow(() -> new ResourceNotFoundException("Unknown workflow: " + type));
        if (slaDays != null) {
            if (slaDays < 1 || slaDays > 10) throw new BadRequestException("The time limit is 1 to 10 days.");
            jdbc.update("UPDATE hq_workflows SET sla_days = ? WHERE type = ?", slaDays, type);
            audit.log("approvals", "Set the " + w.get("label") + " time limit to " + slaDays + " days");
        }
        if (locked != null) {
            jdbc.update("UPDATE hq_workflows SET locked = ? WHERE type = ?", locked, type);
            audit.log("approvals", (locked ? "Fixed" : "Opened") + " the " + w.get("label") + " workflow " + (locked ? "for all academies" : "to academy adjustments"));
        }
    }

    // ---------------------------------------------------------------- creating

    /** Starts a request HQ raises itself (an activation, an exit). Returns its id. */
    @Transactional
    public UUID create(String type, UUID academyId, String requestedBy, String summary, List<List<String>> details,
                       Map<String, Object> payload, int startStage, String refKind, String refId) {
        UUID id = UUID.randomUUID();
        jdbc.update("""
                INSERT INTO hq_requests (id, type, academy_id, requested_by, summary, details, payload, stage, ref_kind, ref_id)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""", id, type, academyId, requestedBy, summary, write(details), write(payload), startStage, refKind, refId);
        history(id, requestedBy, "Submitted the request");
        return id;
    }

    /** Pulls in requests academies have raised from their app, and mirrors answers given outside this console. */
    @Transactional
    public void syncAcademyRequests() {
        var fresh = jdbc.queryForList("""
                SELECT r.id, r.academy_id, r.type, r.status, r.subject, r.details, r.target_email, r.reason, r.target_plan, r.created_at,
                       r.resolution_note, r.resolved_at, a.name, a.owner_name, a.plan, p.display_name AS plan_name, p.monthly_price,
                       t.display_name AS target_name, t.monthly_price AS target_price,
                       (SELECT count(*) FROM academy_memberships m WHERE m.academy_id = a.id AND m.role_type = 'STUDENT' AND m.status = 'ACTIVE') AS students
                FROM academy_requests r JOIN academies a ON a.id = r.academy_id
                LEFT JOIN billing_plans p ON p.code = a.plan LEFT JOIN billing_plans t ON t.code = r.target_plan
                WHERE r.type <> 'SUPPORT' AND NOT EXISTS (SELECT 1 FROM hq_requests h WHERE h.source_id = r.id)
                ORDER BY r.created_at""");
        for (var r : fresh) {
            String type = (String) r.get("type");
            String academy = (String) r.get("name");
            List<List<String>> det = new ArrayList<>();
            Map<String, Object> payload = new LinkedHashMap<>();
            String summary;
            switch (type) {
                case "PLAN_CHANGE" -> {
                    summary = "Change plan from " + nz(r.get("plan_name")) + " to " + nz(r.get("target_name"));
                    det.add(List.of("Current plan", nz(r.get("plan_name")) + (r.get("monthly_price") == null ? "" : " · " + HqBilling.inr((java.math.BigDecimal) r.get("monthly_price")) + " / mo")));
                    det.add(List.of("Requested plan", nz(r.get("target_name")) + (r.get("target_price") == null ? "" : " · " + HqBilling.inr((java.math.BigDecimal) r.get("target_price")) + " / mo")));
                    det.add(List.of("Students", r.get("students") + " now"));
                    det.add(List.of("Effective", "From the next renewal"));
                    payload.put("plan", r.get("target_plan"));
                    payload.put("requested", r.get("target_plan"));
                }
                case "OWNERSHIP_TRANSFER" -> {
                    summary = "Transfer ownership to " + nz(r.get("target_email"));
                    det.add(List.of("Current owner", nz(r.get("owner_name"))));
                    det.add(List.of("New owner email", nz(r.get("target_email"))));
                    if (r.get("reason") != null) det.add(List.of("Reason", (String) r.get("reason")));
                    if (r.get("details") != null) det.add(List.of("Notes", (String) r.get("details")));
                    payload.put("newEmail", r.get("target_email"));
                }
                case "ACADEMY_CLOSURE" -> {
                    summary = "Close the academy and end its subscription";
                    det.add(List.of("Students affected", String.valueOf(r.get("students"))));
                    if (r.get("details") != null) det.add(List.of("Reason", (String) r.get("details")));
                    det.add(List.of("What happens", "Subscription ends and access is removed for everyone linked to it"));
                }
                default -> {
                    summary = "Stop the subscription at the end of the billing period";
                    if (r.get("details") != null) det.add(List.of("Notes", (String) r.get("details")));
                }
            }
            UUID id = UUID.randomUUID();
            Timestamp created = (Timestamp) r.get("created_at");
            String status = (String) r.get("status");
            jdbc.update("""
                    INSERT INTO hq_requests (id, type, academy_id, requested_by, summary, details, payload, stage_since, created_at, source_id, decision, decided_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
                    id, type, r.get("academy_id"), "Owner of " + academy, summary, write(det), write(payload), created, created, r.get("id"),
                    "APPROVED".equals(status) ? "approved" : "DECLINED".equals(status) ? "rejected" : null, r.get("resolved_at"));
            jdbc.update("INSERT INTO hq_request_history (request_id, at, who, text) VALUES (?, ?, ?, ?)", id, created, "Owner of " + academy, "Requested in the academy app");
        }
        // Answered in the old console: keep this record in step.
        jdbc.update("""
                UPDATE hq_requests h SET decision = CASE r.status WHEN 'APPROVED' THEN 'approved' ELSE 'rejected' END, decided_at = r.resolved_at
                FROM academy_requests r WHERE h.source_id = r.id AND h.decision IS NULL AND r.status <> 'PENDING'""");
    }

    // ---------------------------------------------------------------- deciding

    @Transactional
    public void decide(UUID id, String action, String comment) {
        var row = jdbc.queryForList("""
                SELECT r.type, r.stage, r.decision, r.academy_id, r.payload, r.ref_kind, r.ref_id, r.source_id, 'R-' || (1000 + r.seq) AS number, w.stages, w.label
                FROM hq_requests r JOIN hq_workflows w ON w.type = r.type WHERE r.id = ? FOR UPDATE OF r""", id).stream().findFirst()
                .orElseThrow(() -> new ResourceNotFoundException("Request not found."));
        if (row.get("decision") != null) throw new ConflictException("This request has already been decided.");
        List<String> stages = Arrays.asList(((String) row.get("stages")).split(","));
        int stage = Math.min((Integer) row.get("stage"), stages.size() - 1);
        if (!canAct(access.role(), stages.get(stage))) {
            throw new ForbiddenException("Waiting on " + stages.get(stage) + ". Your role cannot act here.");
        }
        String type = (String) row.get("type"), number = (String) row.get("number"), label = (String) row.get("label");
        String note = comment == null ? "" : comment.trim();
        String who = actorName();

        if (!action.equals("approve") && note.length() < 3) throw new BadRequestException("A comment is required.");

        if (action.equals("approve")) {
            if (type.equals("OWNERSHIP_TRANSFER")) {
                throw new BadRequestException("Ownership transfers are completed in Academy transfer, where both owners confirm with a code.");
            }
            if (type.equals("BANK_CHANGE")) {
                throw new BadRequestException("Bank account changes are handled with the Give access / Map gateway steps on the request.");
            }
            if (stage < stages.size() - 1) {
                jdbc.update("UPDATE hq_requests SET stage = ?, stage_since = now() WHERE id = ?", stage + 1, id);
                history(id, who, "Approved" + (note.isEmpty() ? "" : ": " + note) + ". Now with " + stages.get(stage + 1));
                audit.log("approvals", (UUID) row.get("academy_id"), "Approved " + number + " (" + label + "); now with " + stages.get(stage + 1));
                return;
            }
            finalApprove(id, row, type, note);
            finish(id, "approved", who, note, row);
            audit.log("approvals", (UUID) row.get("academy_id"), "Approved " + number + " (" + label + ")");
        } else {
            String decision = action.equals("return") ? "returned" : "rejected";
            finish(id, decision, who, note, row);
            audit.log("approvals", (UUID) row.get("academy_id"), (action.equals("return") ? "Returned " : "Rejected ") + number + " (" + label + ")");
        }
    }

    private void finalApprove(UUID id, Map<String, Object> row, String type, String note) {
        UUID academyId = (UUID) row.get("academy_id");
        Map<String, Object> payload = read((String) row.get("payload"), new TypeReference<Map<String, Object>>() { });
        switch (type) {
            case "PLAN_CHANGE" -> {
                Object plan = payload.get("plan");
                if (plan == null) throw new BadRequestException("Choose the plan to apply first.");
                academyService.changePlan(academyId, plan.toString(), "Approved request " + row.get("number"));
            }
            case "ACADEMY_CLOSURE" -> {
                jdbc.update("UPDATE academies SET closed_at = now(), status = 'SUSPENDED', updated_at = now() WHERE id = ?", academyId);
                audit.log("academies", academyId, "Academy closed (" + row.get("number") + ")");
            }
            default -> { }
        }
    }

    private void finish(UUID id, String decision, String who, String note, Map<String, Object> row) {
        UUID actor = TenantContext.currentUserIdOrNull();
        jdbc.update("UPDATE hq_requests SET decision = ?, decided_at = now(), decided_by = ? WHERE id = ?", decision, actor, id);
        String verb = switch (decision) { case "approved" -> "Approved"; case "returned" -> "Returned"; default -> "Rejected"; };
        history(id, who, verb + (note.isEmpty() ? "" : ": " + note));
        if (row.get("source_id") != null) {
            boolean ok = decision.equals("approved");
            jdbc.update("""
                    UPDATE academy_requests SET status = ?, resolution_note = ?, resolved_by = ?, resolved_at = now() WHERE id = ?""",
                    ok ? "APPROVED" : "DECLINED", note.isEmpty() ? (ok ? null : verb) : (decision.equals("returned") ? "Returned for changes: " : "") + note, actor, row.get("source_id"));
        }
        events.publishEvent(new RequestDecided(id, (String) row.get("type"), decision, (String) row.get("ref_kind"), (String) row.get("ref_id"), (UUID) row.get("academy_id"), note));
    }

    /**
     * Closes an open request from outside the approval screen: an ownership transfer finishing or being
     * rejected in Academy transfer. A request already decided is left as it is.
     */
    @Transactional
    public void closeExternally(UUID id, String decision, String note) {
        var row = jdbc.queryForList("""
                SELECT r.type, r.academy_id, r.ref_kind, r.ref_id, r.source_id, r.decision FROM hq_requests r WHERE r.id = ? FOR UPDATE""", id).stream().findFirst().orElse(null);
        if (row == null || row.get("decision") != null) return;
        finish(id, decision, "System", note == null ? "" : note, row);
    }

    /** HQ picks which plan an approval will apply, which may differ from the one asked for. */
    @Transactional
    public void choosePlan(UUID id, String planCode) {
        var r = jdbc.queryForList("SELECT type, decision, payload, academy_id FROM hq_requests WHERE id = ? FOR UPDATE", id).stream().findFirst()
                .orElseThrow(() -> new ResourceNotFoundException("Request not found."));
        if (!"PLAN_CHANGE".equals(r.get("type"))) throw new BadRequestException("Only a plan change has a plan to choose.");
        if (r.get("decision") != null) throw new ConflictException("This request has already been decided.");
        var plan = jdbc.queryForList("SELECT display_name FROM billing_plans WHERE code = ? AND active", planCode).stream().findFirst()
                .orElseThrow(() -> new BadRequestException("Unknown plan: " + planCode));
        Map<String, Object> payload = read((String) r.get("payload"), new TypeReference<Map<String, Object>>() { });
        payload.put("plan", planCode);
        jdbc.update("UPDATE hq_requests SET payload = ? WHERE id = ?", write(payload), id);
        history(id, actorName(), "Chose the " + plan.get("display_name") + " plan to apply");
    }

    /** A plan change HQ makes on its own: recorded as an already-approved request so the history reads the same. */
    @Transactional
    public void directPlanChange(UUID academyId, String planCode, String reason) {
        var cur = jdbc.queryForList("SELECT a.name, p.display_name FROM academies a LEFT JOIN billing_plans p ON p.code = a.plan WHERE a.id = ?", academyId)
                .stream().findFirst().orElseThrow(() -> new ResourceNotFoundException("Academy not found."));
        academyService.changePlan(academyId, planCode, reason);
        String to = jdbc.queryForObject("SELECT display_name FROM billing_plans WHERE code = ?", String.class, planCode);
        String who = actorName();
        UUID id = create("PLAN_CHANGE", academyId, who, "Changed from " + nz(cur.get("display_name")) + " to " + to + ", changed by HQ" + (reason == null || reason.isBlank() ? "" : " (" + reason + ")"),
                List.of(), Map.of("plan", planCode), 0, null, null);
        jdbc.update("UPDATE hq_requests SET decision = 'approved', decided_at = now(), decided_by = ? WHERE id = ?", TenantContext.currentUserIdOrNull(), id);
        history(id, who, "Changed the plan from " + nz(cur.get("display_name")) + " to " + to);
    }

    // ---------------------------------------------------------------- helpers

    private void history(UUID id, String who, String text) {
        jdbc.update("INSERT INTO hq_request_history (request_id, who, text) VALUES (?, ?, ?)", id, who, text.length() > 400 ? text.substring(0, 399) + "…" : text);
    }

    private String actorName() {
        UUID u = TenantContext.currentUserIdOrNull();
        if (u == null) return "System";
        return access.roleOf(u).label();
    }

    private static String nz(Object o) {
        return o == null ? "" : o.toString();
    }

    private String write(Object o) {
        try {
            return json.writeValueAsString(o);
        } catch (Exception e) {
            throw new IllegalStateException(e);
        }
    }

    private <T> T read(String s, TypeReference<T> t) {
        try {
            return json.readValue(s == null || s.isBlank() ? "null" : s, t);
        } catch (Exception e) {
            throw new IllegalStateException(e);
        }
    }
}
