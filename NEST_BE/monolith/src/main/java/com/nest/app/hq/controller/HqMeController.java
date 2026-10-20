package com.nest.app.hq.controller;

import com.nest.app.hq.HqAccess;
import com.nest.app.hq.HqRole;
import com.nest.common.security.NestPrincipal;
import com.nest.common.security.TenantContext;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

@RestController
@Tag(name = "HQ Console")
@PreAuthorize("hasRole('SUPER_ADMIN')")
public class HqMeController {

    private final HqAccess access;
    private final JdbcTemplate jdbc;

    public HqMeController(HqAccess access, JdbcTemplate jdbc) {
        this.access = access;
        this.jdbc = jdbc;
    }

    /**
     * Who is signed in to the HQ console and what they may open. The web app calls this right after
     * login and uses the module list to lock tiles; the server still checks every request itself.
     */
    @GetMapping("/admin/hq/me")
    public Map<String, Object> me() {
        NestPrincipal p = TenantContext.require();
        HqRole role = access.roleOf(p.userId());
        List<String> names = jdbc.queryForList("SELECT full_name FROM users WHERE id = ?", String.class, p.userId());
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("id", p.userId());
        out.put("username", p.username());
        out.put("fullName", names.isEmpty() ? p.username() : names.get(0));
        out.put("hqRole", role.name());
        out.put("roleLabel", role.label());
        out.put("modules", role.modules());
        out.put("canWrite", role.canWrite());
        out.put("canExport", role.canExport());
        return out;
    }
}
