package com.nest.app.hq.service;

import com.nest.app.hq.HqAudit;
import com.nest.app.hq.HqRole;
import com.nest.app.identity.service.IdentityRegistrationService;
import com.nest.app.identity.service.UserWithTempPassword;
import com.nest.common.exception.BadRequestException;
import com.nest.common.exception.ConflictException;
import com.nest.common.exception.ResourceNotFoundException;
import com.nest.common.security.Role;
import com.nest.common.security.TenantContext;
import jakarta.persistence.EntityManager;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.sql.Timestamp;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.regex.Pattern;

/**
 * The people who work in this console and what each may do. Only a Super admin manages the team,
 * and the platform always keeps at least one active Super admin.
 */
@Service
public class HqTeam {

    private static final Pattern EMAIL = Pattern.compile("^\\S+@\\S+\\.\\S+$");
    private static final Pattern MOBILE = Pattern.compile("^[6-9]\\d{9}$");
    private static final Pattern USERNAME = Pattern.compile("^[a-z0-9._]{4,30}$");

    private final JdbcTemplate jdbc;
    private final HqAudit audit;
    private final IdentityRegistrationService registration;
    private final EntityManager em;

    public HqTeam(JdbcTemplate jdbc, HqAudit audit, IdentityRegistrationService registration, EntityManager em) {
        this.jdbc = jdbc;
        this.audit = audit;
        this.registration = registration;
        this.em = em;
    }

    public Map<String, Object> list() {
        List<Map<String, Object>> members = new ArrayList<>();
        for (var u : jdbc.queryForList("SELECT id, full_name, username, email, hq_role, status, last_seen_at FROM users WHERE role_type = 'SUPER_ADMIN' ORDER BY full_name")) {
            HqRole role = HqRole.of((String) u.get("hq_role"));
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("id", u.get("id"));
            m.put("name", u.get("full_name"));
            m.put("username", u.get("username"));
            m.put("email", u.get("email"));
            m.put("role", role.name());
            m.put("roleLabel", role.label());
            m.put("active", "ACTIVE".equals(u.get("status")));
            m.put("lastSeen", u.get("last_seen_at") == null ? null : ((Timestamp) u.get("last_seen_at")).toInstant());
            members.add(m);
        }
        List<Map<String, Object>> roles = new ArrayList<>();
        for (HqRole r : HqRole.values()) {
            roles.add(Map.of("code", r.name(), "label", r.label(), "description", describe(r), "write", r.canWrite(), "export", r.canExport(),
                    "modules", r.modules().contains("*") ? List.of("*") : r.modules().stream().sorted().toList()));
        }
        return Map.of("members", members, "roles", roles);
    }

    private static String describe(HqRole r) {
        return switch (r) {
            case SUPER -> "Full access, including global changes and managing this team";
            case OPS -> "Academies, users, courses, approvals and exits";
            case FINANCE -> "Payments, plans, growth and reports";
            case SUPPORT -> "Tickets, enquiries, feedback, user lookups and exits";
        };
    }

    private Map<String, Object> staff(UUID id) {
        var rows = jdbc.queryForList("SELECT id, full_name, hq_role, status FROM users WHERE id = ? AND role_type = 'SUPER_ADMIN'", id);
        if (rows.isEmpty()) throw new ResourceNotFoundException("Team member not found");
        return rows.get(0);
    }

    private int activeSupers(UUID except) {
        return jdbc.queryForObject("""
                SELECT count(*) FROM users WHERE role_type = 'SUPER_ADMIN' AND status = 'ACTIVE' AND (hq_role IS NULL OR hq_role = 'SUPER') AND id <> ?""", Integer.class, except);
    }

    @Transactional
    public void setRole(UUID id, String role) {
        var u = staff(id);
        HqRole next;
        try {
            next = HqRole.valueOf(role);
        } catch (Exception e) {
            throw new BadRequestException("Choose a role.");
        }
        HqRole cur = HqRole.of((String) u.get("hq_role"));
        if (cur == next) return;
        if (cur == HqRole.SUPER && activeSupers(id) == 0) throw new BadRequestException("The platform needs at least one active Super admin.");
        jdbc.update("UPDATE users SET hq_role = ?, updated_at = now() WHERE id = ?", next.name(), id);
        audit.log("team", "Changed the role of " + u.get("full_name") + " from " + cur.label() + " to " + next.label());
    }

    @Transactional
    public void setActive(UUID id, boolean active) {
        var u = staff(id);
        if (!active) {
            if (id.equals(TenantContext.currentUserIdOrNull())) throw new BadRequestException("You cannot deactivate yourself.");
            if (HqRole.of((String) u.get("hq_role")) == HqRole.SUPER && activeSupers(id) == 0) throw new BadRequestException("The platform needs at least one active Super admin.");
        }
        jdbc.update("UPDATE users SET status = ?, updated_at = now() WHERE id = ?", active ? "ACTIVE" : "INACTIVE", id);
        if (!active) jdbc.update("UPDATE refresh_tokens SET revoked = TRUE, revoked_at = now() WHERE user_id = ? AND NOT revoked", id);
        audit.log("team", (active ? "Reactivated " : "Deactivated ") + "team member " + u.get("full_name"));
    }

    /** Creates a console login. The temporary password is returned once and must be changed at first sign-in. */
    @Transactional
    public Map<String, Object> invite(String name, String username, String phone, String email, String role) {
        if (name == null || name.trim().length() < 3) throw new BadRequestException("Enter the full name.");
        String un = username == null ? "" : username.trim().toLowerCase();
        if (!USERNAME.matcher(un).matches()) throw new BadRequestException("Username: 4 to 30 letters, numbers, dots or underscores.");
        String ph = phone == null ? "" : phone.replaceAll("\\s", "");
        if (!MOBILE.matcher(ph).matches()) throw new BadRequestException("Enter a 10-digit mobile number.");
        if (email == null || !EMAIL.matcher(email.trim()).matches()) throw new BadRequestException("Enter a valid email address.");
        HqRole r;
        try {
            r = HqRole.valueOf(role);
        } catch (Exception e) {
            throw new BadRequestException("Choose a role.");
        }
        if (jdbc.queryForObject("SELECT count(*) FROM users WHERE username = ? OR lower(email) = lower(?)", Integer.class, un, email.trim()) > 0) {
            throw new ConflictException("That username or email is already in use.");
        }
        UserWithTempPassword created = registration.createUserWithPassword(un, name.trim(), ph, email.trim(), Role.SUPER_ADMIN);
        // The account was saved through JPA; flush so the role update below finds the row. Without this the
        // person would be left with no role set, which the console treats as Super admin.
        em.flush();
        if (jdbc.update("UPDATE users SET hq_role = ? WHERE id = ?", r.name(), created.user().getId()) != 1) {
            throw new IllegalStateException("Could not set the role on the new account");
        }
        audit.log("team", "Added " + name.trim() + " to the team as " + r.label());
        return Map.of("username", created.user().getUsername(), "password", created.temporaryPassword());
    }
}
