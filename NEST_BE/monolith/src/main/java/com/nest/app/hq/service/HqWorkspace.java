package com.nest.app.hq.service;

import com.nest.app.hq.HqAudit;
import com.nest.app.identity.entity.OtpPurpose;
import com.nest.app.identity.service.OtpService;
import com.nest.common.exception.BadRequestException;
import com.nest.common.security.TenantContext;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.sql.Timestamp;
import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

/**
 * The Finance workspace: revenue, collections and invoicing live apart from business operations, and
 * the two are never open together. Opening Finance needs a one-time code sent to the signed-in
 * person's own email; the grant lasts eight hours or until they close it. The server refuses finance
 * data without a live grant, so hiding the screens is not the only protection.
 */
@Service
public class HqWorkspace {

    static final long HOURS = 8;

    private final JdbcTemplate jdbc;
    private final HqAudit audit;
    private final OtpService otp;

    public HqWorkspace(JdbcTemplate jdbc, HqAudit audit, OtpService otp) {
        this.jdbc = jdbc;
        this.audit = audit;
        this.otp = otp;
    }

    public boolean isOpen(UUID userId) {
        return userId != null && Boolean.TRUE.equals(jdbc.queryForObject(
                "SELECT EXISTS (SELECT 1 FROM hq_workspace_grants WHERE user_id = ? AND expires_at > now())", Boolean.class, userId));
    }

    public Map<String, Object> status() {
        UUID me = TenantContext.currentUserId();
        Map<String, Object> out = new LinkedHashMap<>();
        var rows = jdbc.queryForList("SELECT expires_at FROM hq_workspace_grants WHERE user_id = ? AND expires_at > now()", me);
        out.put("finance", !rows.isEmpty());
        out.put("expiresAt", rows.isEmpty() ? null : ((Timestamp) rows.get(0).get("expires_at")).toInstant());
        return out;
    }

    private String email(UUID me) {
        List<String> e = jdbc.queryForList("SELECT email FROM users WHERE id = ?", String.class, me);
        if (e.isEmpty() || e.get(0) == null || e.get(0).isBlank()) {
            throw new BadRequestException("Your account has no email address, so a code cannot be sent. Add one first.");
        }
        return e.get(0);
    }

    /** Sends the code to the person's registered email. */
    @Transactional
    public Map<String, String> sendCode() {
        UUID me = TenantContext.currentUserId();
        String email = email(me);
        otp.requestOtpForEmail(email, OtpPurpose.FINANCE_WORKSPACE, me);
        int at = email.indexOf('@');
        return Map.of("sentTo", at < 3 ? email : email.substring(0, 2) + "•••••" + email.substring(at));
    }

    @Transactional
    public void open(String code) {
        UUID me = TenantContext.currentUserId();
        if (code == null || !code.trim().matches("\\d{6}")) throw new BadRequestException("Enter the 6-digit code.");
        UUID ctx = otp.verifyOtpForEmail(email(me), code.trim(), OtpPurpose.FINANCE_WORKSPACE);
        if (ctx != null && !ctx.equals(me)) throw new BadRequestException("That code was not sent to you. Ask for a new one.");
        jdbc.update("""
                INSERT INTO hq_workspace_grants (user_id, opened_at, expires_at) VALUES (?, now(), ?)
                ON CONFLICT (user_id) DO UPDATE SET opened_at = now(), expires_at = EXCLUDED.expires_at""",
                me, Timestamp.from(Instant.now().plusSeconds(HOURS * 3600)));
        audit.log("workspace", "Opened the Finance workspace");
    }

    @Transactional
    public void close() {
        UUID me = TenantContext.currentUserId();
        if (jdbc.update("DELETE FROM hq_workspace_grants WHERE user_id = ?", me) > 0) audit.log("workspace", "Closed the Finance workspace");
    }
}
