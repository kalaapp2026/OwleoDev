package com.nest.app.hq.service;

import com.nest.app.hq.HqAccess;
import com.nest.app.hq.HqAudit;
import com.nest.app.platform.dto.PlatformSettingsDtos;
import com.nest.app.platform.entity.AppMode;
import com.nest.app.platform.service.PlatformSettingsService;
import com.nest.common.exception.BadRequestException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.lang.management.ManagementFactory;
import java.sql.Timestamp;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * The "Platform status" half of the dashboard: what is owed, how complete the user data is, whether
 * the system itself is healthy, who is using the app, and what is waiting on HQ. Everything is read
 * live; nothing here is estimated.
 */
@Service
public class HqPlatform {

    private final JdbcTemplate jdbc;
    private final HqAcademies academies;
    private final HqUsers users;
    private final HqSupport support;
    private final HqApprovals approvals;
    private final HqAccess access;
    private final HqAudit audit;
    private final PlatformSettingsService settings;

    public HqPlatform(JdbcTemplate jdbc, HqAcademies academies, HqUsers users, HqSupport support, HqApprovals approvals, HqAccess access, HqAudit audit,
                      PlatformSettingsService settings) {
        this.jdbc = jdbc;
        this.academies = academies;
        this.users = users;
        this.support = support;
        this.approvals = approvals;
        this.access = access;
        this.audit = audit;
        this.settings = settings;
    }

    public Map<String, Object> status() {
        var rows = academies.all();
        long live = rows.stream().filter(a -> "live".equals(a.status()) || "pastdue".equals(a.status())).count();
        long demo = rows.stream().filter(a -> "trial".equals(a.status())).count();
        long closed = rows.stream().filter(a -> "churned".equals(a.status())).count();
        Map<String, Object> out = new LinkedHashMap<>();

        out.put("liveAcademies", live);
        out.put("demoAcademies", demo);
        out.put("closedAcademies", closed);
        out.put("admins", jdbc.queryForObject("SELECT count(*) FROM academy_memberships WHERE role_type = 'ACADEMY_ADMIN' AND status = 'ACTIVE'", Integer.class));
        out.put("hqStaff", jdbc.queryForObject("SELECT count(*) FROM users WHERE role_type = 'SUPER_ADMIN' AND status = 'ACTIVE'", Integer.class));

        // Only the NUMBER of overdue academies is shown here. The amounts belong to the Finance workspace.
        out.put("overdueCount", jdbc.queryForObject("""
                SELECT count(DISTINCT i.academy_id) FROM academy_invoices i JOIN academies a ON a.id = i.academy_id
                WHERE i.status <> 'PAID' AND i.due_on < current_date AND a.closed_at IS NULL""", Integer.class));

        // Users and how complete their data is.
        Map<String, Object> u = users.summary();
        out.put("userOverview", Map.of("profiles", u.get("profiles"), "missing", u.get("missing"), "missingTop", u.get("missingTop"),
                "active", jdbc.queryForObject("SELECT count(*) FROM users WHERE last_seen_at > now() - interval '30 days' AND role_type <> 'SUPER_ADMIN'", Integer.class)));

        out.put("health", health());
        out.put("traffic", traffic());
        out.put("support", support.counts());
        out.put("approvals", approvals.counts());
        return out;
    }

    private Map<String, Object> health() {
        long t0 = System.nanoTime();
        jdbc.queryForObject("SELECT 1", Integer.class);
        long dbMs = Math.max(1, (System.nanoTime() - t0) / 1_000_000);
        Runtime rt = Runtime.getRuntime();
        long used = rt.totalMemory() - rt.freeMemory(), max = rt.maxMemory();
        long uptimeMin = ManagementFactory.getRuntimeMXBean().getUptime() / 60000;
        int sessions = jdbc.queryForObject("SELECT count(*) FROM refresh_tokens WHERE NOT revoked AND expires_at > now()", Integer.class);
        int failed = jdbc.queryForObject("SELECT count(*) FROM notification_deliveries WHERE status NOT IN ('SENT') AND created_at > now() - interval '24 hours'", Integer.class);
        int sent = jdbc.queryForObject("SELECT count(*) FROM notification_deliveries WHERE status = 'SENT' AND created_at > now() - interval '24 hours'", Integer.class);

        List<Map<String, Object>> checks = new ArrayList<>();
        checks.add(check("Database", dbMs + " ms", dbMs < 200 ? "green" : dbMs < 1000 ? "gold" : "red", "Round trip for a simple query"));
        checks.add(check("Server memory", Math.round(used * 100.0 / max) + "% used", used * 100.0 / max < 80 ? "green" : used * 100.0 / max < 92 ? "gold" : "red", Math.round(used / 1048576.0) + " MB of " + Math.round(max / 1048576.0) + " MB"));
        checks.add(check("Uptime", uptimeMin >= 1440 ? (uptimeMin / 1440) + "d " + (uptimeMin % 1440 / 60) + "h" : uptimeMin >= 60 ? (uptimeMin / 60) + "h " + (uptimeMin % 60) + "m" : uptimeMin + "m", "green", "Since the server last started"));
        checks.add(check("Signed-in sessions", String.valueOf(sessions), "green", "Refresh tokens that are still valid"));
        checks.add(check("Notifications", failed == 0 ? "All delivered" : failed + " not delivered", failed == 0 ? "green" : failed < 10 ? "gold" : "red", sent + " sent in the last 24 hours"));

        List<Map<String, Object>> incidents = new ArrayList<>();
        for (var r : jdbc.queryForList("""
                SELECT d.event_key, d.channel, d.status, d.detail, d.created_at FROM notification_deliveries d
                WHERE d.status NOT IN ('SENT') ORDER BY d.created_at DESC LIMIT 5""")) {
            incidents.add(Map.of("what", r.get("event_key") + " by " + r.get("channel"), "status", r.get("status"), "detail", r.get("detail") == null ? "" : r.get("detail"),
                    "at", ((Timestamp) r.get("created_at")).toLocalDateTime().atZone(java.time.ZoneId.systemDefault()).toInstant()));
        }
        return Map.of("checks", checks, "incidents", incidents);
    }

    private static Map<String, Object> check(String name, String value, String tone, String note) {
        return Map.of("name", name, "value", value, "tone", tone, "note", note);
    }

    private Map<String, Object> traffic() {
        List<Map<String, Object>> active = jdbc.queryForList("""
                SELECT a.id, a.name, count(DISTINCT u.id) AS seen,
                       (SELECT count(*) FROM academy_memberships m2 WHERE m2.academy_id = a.id AND m2.status = 'ACTIVE') AS members
                FROM academies a JOIN academy_memberships m ON m.academy_id = a.id AND m.status = 'ACTIVE' JOIN users u ON u.id = m.user_id
                WHERE a.closed_at IS NULL AND u.last_seen_at >= current_date
                GROUP BY a.id, a.name ORDER BY seen DESC LIMIT 5""");
        return Map.of("academies", active, "owners", sessions("ACADEMY_ADMIN"), "students", sessions("STUDENT"));
    }

    /** Sign-ins in the last 7 days per person, most first. */
    private List<Map<String, Object>> sessions(String role) {
        return jdbc.queryForList("""
                SELECT u.full_name AS name, (SELECT a.name FROM academy_memberships m JOIN academies a ON a.id = m.academy_id WHERE m.user_id = u.id ORDER BY m.created_at LIMIT 1) AS academy,
                       count(*) AS sessions
                FROM refresh_tokens rt JOIN users u ON u.id = rt.user_id
                WHERE u.role_type = ? AND rt.issued_at > now() - interval '7 days'
                GROUP BY u.id, u.full_name ORDER BY sessions DESC, u.full_name LIMIT 5""", role);
    }

    // ---------------------------------------------------------------- app mode (Platform settings)

    public Map<String, Object> appMode() {
        PlatformSettingsDtos.Response cur = current();
        return Map.of("mode", cur.appMode().name(), "history", audit.recent("settings", null, 8));
    }

    private PlatformSettingsDtos.Response current() {
        AppMode m = settings.current().getAppMode();
        return new PlatformSettingsDtos.Response(m, m.allowsErp(), m.allowsSocial(), m.allowsBoth(), m.startsOnErp());
    }

    @Transactional
    public void setAppMode(String mode) {
        access.requireSuper();
        AppMode next;
        try {
            next = AppMode.valueOf(mode);
        } catch (Exception e) {
            throw new BadRequestException("Choose an app mode.");
        }
        AppMode from = settings.current().getAppMode();
        if (from == next) return;
        settings.updateAppMode(next);
        audit.log("settings", "Platform app mode: " + label(from) + " to " + label(next));
    }

    private static String label(AppMode m) {
        return switch (m) { case ERP_FIRST -> "ERP first"; case SOCIAL_FIRST -> "Social first"; case ERP_ONLY -> "ERP only"; case SOCIAL_ONLY -> "Social only"; };
    }

}
