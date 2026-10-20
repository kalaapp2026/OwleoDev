package com.nest.app.hq;

import com.nest.common.exception.ForbiddenException;
import com.nest.common.security.TenantContext;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;

import java.util.List;
import java.util.UUID;

/**
 * The one place that answers "may this HQ person do that?". Controllers under {@code /admin/hq}
 * call {@link #requireModule} / {@link #requireWrite} / {@link #requireSuper} at the top of each
 * method. It reads {@code hq_role} live on every call rather than trusting the login token, so
 * changing a staff member's role takes effect immediately - the same reasoning as the academy
 * app's live feature-grant lookup.
 *
 * <p>This sits behind the coarse {@code hasRole('SUPER_ADMIN')} gate on the controllers: that
 * keeps students and trainers out entirely, this narrows HQ staff to their own area.
 */
@Component
public class HqAccess {

    private final JdbcTemplate jdbc;

    public HqAccess(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public HqRole role() {
        return roleOf(TenantContext.currentUserId());
    }

    public HqRole roleOf(UUID userId) {
        List<String> rows = jdbc.queryForList("SELECT hq_role FROM users WHERE id = ?", String.class, userId);
        return rows.isEmpty() ? HqRole.SUPER : HqRole.of(rows.get(0));
    }

    public void requireModule(String module) {
        if (!role().canOpen(module)) {
            throw new ForbiddenException(role().label() + " cannot open " + module);
        }
    }

    public void requireWrite() {
        if (!role().canWrite()) {
            throw new ForbiddenException("The " + role().label() + " role can view this but not change it");
        }
    }

    public void requireSuper() {
        if (role() != HqRole.SUPER) {
            throw new ForbiddenException("Only a Super admin can do this");
        }
    }

    public void requireExport() {
        if (!role().canExport()) {
            throw new ForbiddenException("The " + role().label() + " role cannot export");
        }
    }
}
