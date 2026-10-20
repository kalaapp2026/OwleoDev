package com.nest.app.hq.service;

import com.nest.app.hq.HqAudit;
import com.nest.common.exception.BadRequestException;
import com.nest.common.exception.ConflictException;
import com.nest.common.exception.ResourceNotFoundException;
import org.springframework.context.event.EventListener;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

/**
 * A person leaving, in four steps: an approval through the EXIT workflow, three clearances (dues,
 * handover, assets), then access is removed. The profile and its history are always kept.
 *
 * <p>An exit can cover every academy the person belongs to, or just one. Removing one leaves the
 * others, and the account itself, untouched.
 */
@Service
public class HqExits {

    private final JdbcTemplate jdbc;
    private final HqAudit audit;
    private final HqApprovals approvals;
    private final HqUsers users;

    public HqExits(JdbcTemplate jdbc, HqAudit audit, HqApprovals approvals, HqUsers users) {
        this.jdbc = jdbc;
        this.audit = audit;
        this.approvals = approvals;
        this.users = users;
    }

    private static String refOf(long seq) {
        return "X-" + (200 + seq);
    }

    private static String state(Map<String, Object> r) {
        String stage = (String) r.get("stage");
        if ("CLEARANCE".equals(stage) && (Boolean) r.get("c_dues") && (Boolean) r.get("c_handover") && (Boolean) r.get("c_assets")) return "ready";
        return stage.toLowerCase();
    }

    public Map<String, Object> list() {
        var rows = jdbc.queryForList("""
                SELECT x.id, x.seq, x.user_id, x.academy_id, x.reason, x.effective_on, x.stage, x.c_dues, x.c_handover, x.c_assets, x.approval_id,
                       u.full_name, pm.role_type, pm.academy_id AS home_id, pm.academy_name AS home,
                       ea.name AS scope_name, (SELECT r.seq FROM hq_requests r WHERE r.id = x.approval_id) AS request_seq,
                       (SELECT count(DISTINCT m.academy_id) FROM academy_memberships m WHERE m.user_id = x.user_id AND m.status IN ('ACTIVE', 'REVOKED')) AS academies
                FROM hq_exits x JOIN users u ON u.id = x.user_id
                LEFT JOIN academies ea ON ea.id = x.academy_id
                LEFT JOIN LATERAL (SELECT m.role_type, m.academy_id, a.name AS academy_name FROM academy_memberships m JOIN academies a ON a.id = m.academy_id
                                    WHERE m.user_id = x.user_id AND m.status IN ('ACTIVE', 'REVOKED') ORDER BY (m.status = 'ACTIVE') DESC, m.created_at LIMIT 1) pm ON TRUE
                WHERE x.stage <> 'REJECTED' ORDER BY x.created_at DESC""");
        List<Map<String, Object>> items = new java.util.ArrayList<>();
        int approval = 0, clearance = 0, ready = 0, done = 0;
        for (var r : rows) {
            String s = state(r);
            switch (s) {
                case "approval" -> approval++;
                case "clearance" -> clearance++;
                case "ready" -> ready++;
                case "done" -> done++;
                default -> { }
            }
            Map<String, Object> m = new LinkedHashMap<>();
            UUID uid = (UUID) r.get("user_id");
            m.put("id", r.get("id"));
            m.put("ref", refOf(((Number) r.get("seq")).longValue()));
            m.put("userId", uid);
            m.put("userRef", users.refOf(uid));
            m.put("name", r.get("full_name"));
            m.put("role", switch ((String) r.get("role_type")) { case "STUDENT" -> "Student"; case "TRAINER" -> "Trainer"; default -> "Admin"; });
            m.put("academy", r.get("home"));
            m.put("homeId", r.get("home_id"));
            m.put("scopeAcademyId", r.get("academy_id"));
            m.put("scope", r.get("scope_name"));
            m.put("multi", ((Number) r.get("academies")).intValue() > 1 || r.get("academy_id") != null);
            m.put("reason", r.get("reason"));
            m.put("effective", r.get("effective_on"));
            m.put("state", s);
            m.put("checks", List.of(r.get("c_dues"), r.get("c_handover"), r.get("c_assets")));
            m.put("approval", r.get("request_seq") == null ? null : "R-" + (1000 + ((Number) r.get("request_seq")).longValue()));
            items.add(m);
        }
        return Map.of("items", items, "approval", approval, "clearance", clearance, "ready", ready, "done", done);
    }

    @Transactional
    public UUID create(UUID userId, UUID academyId, String reason, String effective) {
        var u = jdbc.queryForList("SELECT full_name FROM users WHERE id = ? AND role_type <> 'SUPER_ADMIN'", userId);
        if (u.isEmpty()) throw new ResourceNotFoundException("Person not found");
        if (reason == null || reason.isBlank()) throw new BadRequestException("Choose a reason.");
        LocalDate eff;
        try {
            eff = LocalDate.parse(effective);
        } catch (Exception e) {
            throw new BadRequestException("Choose the effective date.");
        }
        if (academyId != null && jdbc.queryForObject("SELECT count(*) FROM academy_memberships WHERE user_id = ? AND academy_id = ? AND status = 'ACTIVE'", Integer.class, userId, academyId) == 0) {
            throw new BadRequestException("This person is not active in that academy.");
        }
        if (jdbc.queryForObject("SELECT count(*) FROM hq_exits WHERE user_id = ? AND stage IN ('APPROVAL', 'CLEARANCE') AND academy_id IS NOT DISTINCT FROM ?", Integer.class, userId, academyId) > 0) {
            throw new ConflictException("An exit is already open for this person.");
        }
        UUID id = UUID.randomUUID();
        jdbc.update("INSERT INTO hq_exits (id, user_id, academy_id, reason, effective_on) VALUES (?, ?, ?, ?, ?)", id, userId, academyId, reason.trim(), eff);
        String name = (String) u.get(0).get("full_name");
        // Raised by HQ, so it starts at the Operations stage: the owner's stage is for requests an academy raises.
        UUID home = academyId != null ? academyId : jdbc.queryForList(
                "SELECT academy_id FROM academy_memberships WHERE user_id = ? AND status = 'ACTIVE' ORDER BY created_at LIMIT 1", UUID.class, userId)
                .stream().findFirst().orElse(null);
        UUID req = approvals.create("EXIT", home, "Owleo HQ", "Exit of " + name + ": " + reason.trim(),
                List.of(List.of("Person", name), List.of("Effective", eff.toString())), Map.of(), 1, "exit", id.toString());
        jdbc.update("UPDATE hq_exits SET approval_id = ? WHERE id = ?", req, id);
        audit.log("exits", academyId, "Started an exit for " + name + " (" + users.refOf(userId) + "): " + reason.trim());
        return id;
    }

    /** The approval's answer moves the exit on, or ends it. */
    @EventListener
    @Transactional
    public void onRequestDecided(HqApprovals.RequestDecided e) {
        if (!"EXIT".equals(e.type()) || !"exit".equals(e.refKind())) return;
        UUID id = UUID.fromString(e.refId());
        if ("approved".equals(e.decision())) {
            jdbc.update("UPDATE hq_exits SET stage = 'CLEARANCE' WHERE id = ? AND stage = 'APPROVAL'", id);
        } else if ("rejected".equals(e.decision())) {
            jdbc.update("UPDATE hq_exits SET stage = 'REJECTED' WHERE id = ? AND stage = 'APPROVAL'", id);
        }
    }

    private Map<String, Object> exit(UUID id) {
        var rows = jdbc.queryForList("SELECT x.*, u.full_name FROM hq_exits x JOIN users u ON u.id = x.user_id WHERE x.id = ?", id);
        if (rows.isEmpty()) throw new ResourceNotFoundException("Exit not found");
        return rows.get(0);
    }

    @Transactional
    public void clearance(UUID id, int index, boolean done) {
        var x = exit(id);
        if (!"CLEARANCE".equals(x.get("stage"))) throw new BadRequestException("Clearances open once the exit is approved.");
        String col = switch (index) { case 0 -> "c_dues"; case 1 -> "c_handover"; case 2 -> "c_assets"; default -> throw new BadRequestException("Unknown clearance."); };
        jdbc.update("UPDATE hq_exits SET " + col + " = ? WHERE id = ?", done, id);
        String label = switch (index) { case 0 -> "Outstanding dues cleared"; case 1 -> "Responsibilities handed over"; default -> "Assets and data returned"; };
        audit.log("exits", (UUID) x.get("academy_id"), (done ? "Ticked " : "Unticked ") + label + " for " + x.get("full_name"));
    }

    @Transactional
    public void complete(UUID id) {
        var x = exit(id);
        if (!"CLEARANCE".equals(x.get("stage"))) throw new BadRequestException("This exit is not ready.");
        if (!(Boolean) x.get("c_dues") || !(Boolean) x.get("c_handover") || !(Boolean) x.get("c_assets")) throw new BadRequestException("Finish all three clearances first.");
        UUID uid = (UUID) x.get("user_id"), academy = (UUID) x.get("academy_id");
        String name = (String) x.get("full_name");
        if (academy == null) {
            users.deactivateOrRestore(uid, false);
        } else {
            jdbc.update("UPDATE academy_memberships SET status = 'REVOKED' WHERE user_id = ? AND academy_id = ? AND status = 'ACTIVE'", uid, academy);
            if (jdbc.queryForObject("SELECT count(*) FROM academy_memberships WHERE user_id = ? AND status = 'ACTIVE'", Integer.class, uid) == 0) {
                users.deactivateOrRestore(uid, false);
            }
        }
        jdbc.update("UPDATE hq_exits SET stage = 'DONE', done_at = now() WHERE id = ?", id);
        jdbc.update("INSERT INTO hq_user_history (user_id, kind, to_value, reason, actor_name) VALUES (?, 'STATUS', 'Inactive', 'Exit completed', ?)",
                uid, jdbc.queryForObject("SELECT COALESCE((SELECT full_name FROM users WHERE id = ?), 'System')", String.class, com.nest.common.security.TenantContext.currentUserIdOrNull()));
        audit.log("exits", academy, "Completed the exit of " + name + " (" + users.refOf(uid) + "), access removed");
    }
}
