package com.nest.app.hq.service;

import com.nest.app.hq.HqAudit;
import com.nest.common.exception.BadRequestException;
import com.nest.common.exception.ConflictException;
import com.nest.common.exception.ResourceNotFoundException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

/**
 * Platform-wide lists (batch types, roles, categories) and the profile fields every academy must
 * collect. A Super admin maintains them; everyone else can read. Nothing here is ever deleted:
 * deactivating hides an item from new choices while records that use it keep it.
 */
@Service
public class HqMaster {

    private static final Map<String, String> KINDS = Map.of("batches", "BATCH_TYPE", "roles", "ROLE", "cats", "CATEGORY");
    private static final Map<String, String> SINGULAR = Map.of("batches", "batch type", "roles", "role", "cats", "category");

    private final JdbcTemplate jdbc;
    private final HqAudit audit;

    public HqMaster(JdbcTemplate jdbc, HqAudit audit) {
        this.jdbc = jdbc;
        this.audit = audit;
    }

    private static String kind(String tab) {
        String k = KINDS.get(tab);
        if (k == null) throw new BadRequestException("Unknown list.");
        return k;
    }

    /** Items of one list, each with how widely it is used where that can be measured. */
    public List<Map<String, Object>> items(String tab) {
        String kind = kind(tab);
        List<Map<String, Object>> out = new java.util.ArrayList<>();
        for (var r : jdbc.queryForList("SELECT id, name, active FROM hq_master_items WHERE kind = ? ORDER BY created_at, name", kind)) {
            Map<String, Object> m = new LinkedHashMap<>(r);
            String name = (String) r.get("name");
            Map<String, Object> use = usage(kind, name);
            m.put("academies", use.get("academies"));
            m.put("users", use.get("users"));
            out.add(m);
        }
        return out;
    }

    private Map<String, Object> usage(String kind, String name) {
        Map<String, Object> u = new LinkedHashMap<>();
        u.put("academies", null);
        u.put("users", null);
        if ("CATEGORY".equals(kind)) {
            String cat = HqAcademies.categoryOf(name);
            u.put("academies", jdbc.queryForObject("SELECT count(*) FROM academies WHERE category = ? AND closed_at IS NULL", Integer.class, cat));
            u.put("users", jdbc.queryForObject("""
                    SELECT count(*) FROM academy_memberships m JOIN academies a ON a.id = m.academy_id
                    WHERE a.category = ? AND a.closed_at IS NULL AND m.status = 'ACTIVE'""", Integer.class, cat));
        } else if ("ROLE".equals(kind)) {
            String role = switch (name) {
                case "Owner", "Academy admin" -> "ACADEMY_ADMIN";
                case "Trainer" -> "TRAINER";
                case "Student" -> "STUDENT";
                default -> null;
            };
            if (role != null) {
                u.put("academies", jdbc.queryForObject("SELECT count(DISTINCT academy_id) FROM academy_memberships WHERE role_type = ? AND status = 'ACTIVE'", Integer.class, role));
                u.put("users", jdbc.queryForObject("SELECT count(*) FROM academy_memberships WHERE role_type = ? AND status = 'ACTIVE'", Integer.class, role));
            }
        }
        return u;
    }

    @Transactional
    public void add(String tab, String name) {
        String kind = kind(tab);
        String n = name == null ? "" : name.trim();
        if (n.length() < 2) throw new BadRequestException("Enter a name.");
        if (n.length() > 80) throw new BadRequestException("Keep the name under 80 characters.");
        if (jdbc.queryForObject("SELECT count(*) FROM hq_master_items WHERE kind = ? AND lower(name) = lower(?)", Integer.class, kind, n) > 0) {
            throw new ConflictException("This " + SINGULAR.get(tab) + " already exists.");
        }
        jdbc.update("INSERT INTO hq_master_items (kind, name) VALUES (?, ?)", kind, n);
        audit.log("master", "Added " + SINGULAR.get(tab) + " " + n);
    }

    @Transactional
    public void setActive(UUID id, boolean active) {
        var rows = jdbc.queryForList("SELECT kind, name FROM hq_master_items WHERE id = ?", id);
        if (rows.isEmpty()) throw new ResourceNotFoundException("Item not found");
        jdbc.update("UPDATE hq_master_items SET active = ? WHERE id = ?", active, id);
        String kind = (String) rows.get(0).get("kind");
        String what = switch (kind) { case "BATCH_TYPE" -> "batch type"; case "ROLE" -> "role"; default -> "category"; };
        audit.log("master", (active ? "Reactivated " : "Deactivated ") + what + " " + rows.get(0).get("name"));
    }

    @Transactional
    public void setRequired(String field, boolean required) {
        var rows = jdbc.queryForList("SELECT label FROM hq_required_fields WHERE field = ?", field);
        if (rows.isEmpty()) throw new ResourceNotFoundException("Unknown field");
        jdbc.update("UPDATE hq_required_fields SET required = ? WHERE field = ?", required, field);
        audit.log("master", (required ? "Made " : "Stopped requiring ") + rows.get(0).get("label") + (required ? " a mandatory field for every academy" : " on every academy"));
    }
}
