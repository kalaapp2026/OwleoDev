package com.nest.app.hq;

import com.nest.common.security.TenantContext;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

/**
 * Writes the HQ audit trail: one plain sentence per thing an HQ person did ("Approved R-1049").
 * Services call {@link #log} inside the same transaction as the change, so a rolled-back change
 * leaves no trail and a committed one always has one.
 */
@Component
public class HqAudit {

    private final JdbcTemplate jdbc;
    private final HqAccess access;

    public HqAudit(JdbcTemplate jdbc, HqAccess access) {
        this.jdbc = jdbc;
        this.access = access;
    }

    public void log(String area, String detail) {
        log(area, null, detail);
    }

    /** [academyId] ties the entry to an academy so its profile can list "recent changes". */
    public void log(String area, UUID academyId, String detail) {
        UUID actor = TenantContext.currentUserIdOrNull();
        String name = "System";
        String role = HqRole.SUPER.name();
        if (actor != null) {
            List<String> names = jdbc.queryForList("SELECT full_name FROM users WHERE id = ?", String.class, actor);
            if (!names.isEmpty()) {
                name = names.get(0);
            }
            role = access.roleOf(actor).name();
        }
        jdbc.update("""
                INSERT INTO hq_audit_log (actor_id, actor_name, actor_role, area, academy_id, detail)
                VALUES (?, ?, ?, ?, ?, ?)""", actor, name, role, area, academyId, trim(detail, 600));
    }

    /** Newest first. {@code area} / {@code academyId} may be null for no filter. */
    public List<Map<String, Object>> recent(String area, UUID academyId, int limit) {
        StringBuilder sql = new StringBuilder("""
                SELECT occurred_at, actor_name, actor_role, area, detail FROM hq_audit_log WHERE 1 = 1""");
        List<Object> args = new java.util.ArrayList<>();
        if (area != null) {
            sql.append(" AND area = ?");
            args.add(area);
        }
        if (academyId != null) {
            sql.append(" AND academy_id = ?");
            args.add(academyId);
        }
        sql.append(" ORDER BY occurred_at DESC LIMIT ?");
        args.add(limit);
        return jdbc.queryForList(sql.toString(), args.toArray()).stream().map(r -> {
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("at", ((java.sql.Timestamp) r.get("occurred_at")).toInstant());
            m.put("who", HqRole.of((String) r.get("actor_role")).label());
            m.put("name", r.get("actor_name"));
            m.put("area", r.get("area") == null ? "" : r.get("area"));
            m.put("text", r.get("detail"));
            return m;
        }).toList();
    }

    private static String trim(String s, int max) {
        return s.length() <= max ? s : s.substring(0, max - 1) + "…";
    }
}
