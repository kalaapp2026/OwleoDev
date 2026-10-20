package com.nest.app.hq.service;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.nest.app.hq.HqAudit;
import com.nest.app.identity.entity.OtpPurpose;
import com.nest.app.identity.service.IdentityRegistrationService;
import com.nest.app.identity.service.OtpService;
import com.nest.app.identity.service.UserWithTempPassword;
import com.nest.common.crypto.PiiEncryptor;
import com.nest.common.exception.BadRequestException;
import com.nest.common.exception.ConflictException;
import com.nest.common.exception.ResourceNotFoundException;
import com.nest.common.security.Role;
import com.nest.common.security.TenantContext;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.sql.Timestamp;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.regex.Pattern;

/**
 * Academy transfer. An academy changes hands only after the current owner (a code to their phone)
 * and the new owner (a code to their email) have each confirmed. Codes come from the same OTP
 * service the rest of the app uses, so a real sender delivers them in production.
 *
 * <p>Completing the transfer makes the new owner an ACADEMY_ADMIN of the academy (creating the
 * account if their email is new, and returning the first sign-in once), removes the previous owner's
 * admin access, and updates the owner on the academy record.
 */
@Service
public class HqTransfers {

    private static final Pattern EMAIL = Pattern.compile("^\\S+@\\S+\\.\\S+$");
    private static final Pattern MOBILE = Pattern.compile("^[6-9]\\d{9}$");
    private static final Duration RESEND_GAP = Duration.ofSeconds(15);

    private final JdbcTemplate jdbc;
    private final HqAudit audit;
    private final OtpService otp;
    private final PiiEncryptor encryptor;
    private final IdentityRegistrationService registration;
    private final HqApprovals approvals;
    private final ObjectMapper json;

    public HqTransfers(JdbcTemplate jdbc, HqAudit audit, OtpService otp, PiiEncryptor encryptor, IdentityRegistrationService registration,
                       HqApprovals approvals, ObjectMapper json) {
        this.jdbc = jdbc;
        this.audit = audit;
        this.otp = otp;
        this.encryptor = encryptor;
        this.registration = registration;
        this.approvals = approvals;
        this.json = json;
    }

    private static String ref(long seq) {
        return "T-" + (297 + seq);
    }

    private static String maskPhone(String p) {
        return p == null || p.length() < 6 ? "" : p.substring(0, 2) + "••••••" + p.substring(p.length() - 2);
    }

    private static String maskEmail(String e) {
        int at = e == null ? -1 : e.indexOf('@');
        return at < 3 ? (e == null ? "" : e) : e.substring(0, 2) + "•••••" + e.substring(at);
    }

    private static String titleCase(String email) {
        String local = email.substring(0, Math.max(1, email.indexOf('@'))).replaceAll("[._\\-0-9]+", " ").trim();
        StringBuilder sb = new StringBuilder();
        for (String w : local.split("\\s+")) {
            if (w.isEmpty()) continue;
            sb.append(Character.toUpperCase(w.charAt(0))).append(w.substring(1).toLowerCase()).append(' ');
        }
        return sb.toString().trim();
    }

    /** The current owner's contact: the academy record first, else the academy's first admin account. */
    private Map<String, String> currentOwner(UUID academyId) {
        var a = jdbc.queryForList("SELECT owner_name, owner_phone, owner_email FROM academies WHERE id = ?", academyId).get(0);
        String name = (String) a.get("owner_name"), phone = (String) a.get("owner_phone"), email = (String) a.get("owner_email");
        if (phone == null || phone.isBlank() || name == null || name.isBlank() || email == null || email.isBlank()) {
            var u = jdbc.queryForList("""
                    SELECT u.full_name, u.phone, u.email FROM academy_memberships m JOIN users u ON u.id = m.user_id
                    WHERE m.academy_id = ? AND m.role_type = 'ACADEMY_ADMIN' AND m.status = 'ACTIVE' ORDER BY m.created_at LIMIT 1""", academyId);
            if (!u.isEmpty()) {
                if (name == null || name.isBlank()) name = (String) u.get(0).get("full_name");
                if (phone == null || phone.isBlank()) phone = u.get(0).get("phone") == null ? null : encryptor.decrypt((String) u.get(0).get("phone"));
                if (email == null || email.isBlank()) email = (String) u.get(0).get("email");
            }
        }
        Map<String, String> m = new LinkedHashMap<>();
        m.put("name", name == null ? "" : name);
        m.put("phone", phone);
        m.put("email", email);
        return m;
    }

    // ---------------------------------------------------------------- reading

    public Map<String, Object> list() {
        var rows = jdbc.queryForList("""
                SELECT t.*, a.name AS academy, (SELECT 'R-' || (1000 + r.seq) FROM hq_requests r WHERE r.id = t.request_id) AS request_ref
                FROM hq_transfers t JOIN academies a ON a.id = t.academy_id ORDER BY t.created_at DESC""");
        int open = 0, review = 0, otpN = 0, done = 0, rejected = 0;
        List<Map<String, Object>> items = new ArrayList<>();
        for (var t : rows) {
            String step = (String) t.get("step");
            switch (step) {
                case "REVIEW" -> { open++; review++; }
                case "OTP" -> { open++; otpN++; }
                case "DONE" -> done++;
                default -> rejected++;
            }
            UUID academyId = (UUID) t.get("academy_id");
            Map<String, String> owner = "DONE".equals(step) ? Map.of("name", nz(t.get("previous_owner")), "phone", "", "email", "") : currentOwner(academyId);
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("id", t.get("id"));
            m.put("ref", ref(((Number) t.get("seq")).longValue()));
            m.put("request", t.get("request_ref"));
            m.put("academyId", academyId);
            m.put("academy", t.get("academy"));
            m.put("currentOwner", "DONE".equals(step) ? nz(t.get("previous_owner")) : owner.get("name"));
            m.put("fromDest", maskPhone(owner.get("phone")) + (owner.get("email") == null || owner.get("email").isBlank() ? "" : " and " + maskEmail(owner.get("email"))));
            m.put("newOwner", t.get("new_name"));
            m.put("newEmail", t.get("new_email"));
            m.put("toDest", maskEmail((String) t.get("new_email")));
            m.put("reason", t.get("reason"));
            m.put("notes", t.get("notes"));
            m.put("step", step.toLowerCase());
            m.put("verifiedFrom", t.get("verified_from"));
            m.put("verifiedTo", t.get("verified_to"));
            m.put("sentFrom", t.get("sent_from_at") == null ? null : ((Timestamp) t.get("sent_from_at")).toInstant());
            m.put("sentTo", t.get("sent_to_at") == null ? null : ((Timestamp) t.get("sent_to_at")).toInstant());
            m.put("why", t.get("why"));
            m.put("doneAt", t.get("done_at") == null ? null : ((Timestamp) t.get("done_at")).toInstant());
            m.put("history", jdbc.queryForList("SELECT text AS x, actor_name AS who, at FROM hq_transfer_history WHERE transfer_id = ? ORDER BY at DESC", t.get("id")));
            items.add(m);
        }
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("items", items);
        out.put("open", open);
        out.put("review", review);
        out.put("otp", otpN);
        out.put("done", done);
        out.put("rejected", rejected);
        out.put("academies", jdbc.queryForList("SELECT id, name FROM academies WHERE closed_at IS NULL ORDER BY name"));
        return out;
    }

    private static String nz(Object o) {
        return o == null ? "" : o.toString();
    }

    private Map<String, Object> transfer(UUID id) {
        var rows = jdbc.queryForList("SELECT * FROM hq_transfers WHERE id = ?", id);
        if (rows.isEmpty()) throw new ResourceNotFoundException("Transfer not found");
        return rows.get(0);
    }

    private String actor() {
        UUID a = TenantContext.currentUserIdOrNull();
        var n = a == null ? List.<String>of() : jdbc.queryForList("SELECT full_name FROM users WHERE id = ?", String.class, a);
        return n.isEmpty() ? "System" : n.get(0);
    }

    private void history(UUID id, String who, String text) {
        jdbc.update("INSERT INTO hq_transfer_history (transfer_id, actor_name, text) VALUES (?, ?, ?)", id, who, text);
    }

    // ---------------------------------------------------------------- opening

    /** Opens (or returns) the transfer for an ownership request that arrived through Approvals. */
    @Transactional
    public UUID openFromRequest(UUID requestId) {
        var existing = jdbc.queryForList("SELECT id FROM hq_transfers WHERE request_id = ? AND step <> 'REJECTED'", UUID.class, requestId);
        if (!existing.isEmpty()) return existing.get(0);
        var r = jdbc.queryForList("SELECT academy_id, type, decision, payload, details FROM hq_requests WHERE id = ?", requestId).stream().findFirst()
                .orElseThrow(() -> new ResourceNotFoundException("Request not found"));
        if (!"OWNERSHIP_TRANSFER".equals(r.get("type"))) throw new BadRequestException("This is not an ownership transfer request.");
        if (r.get("decision") != null) throw new ConflictException("This request was already decided.");
        Map<String, Object> payload = read((String) r.get("payload"));
        String email = nz(payload.get("newEmail")).trim();
        String reason = "Other", notes = null;
        try {
            List<List<String>> det = json.readValue((String) r.get("details"), new TypeReference<>() { });
            for (var p : det) {
                if ("Reason".equals(p.get(0))) reason = p.get(1);
                if ("Notes".equals(p.get(0))) notes = p.get(1);
            }
        } catch (Exception ignored) {
            // keep defaults
        }
        if (!EMAIL.matcher(email).matches()) throw new BadRequestException("The request has no valid new owner email.");
        return insert((UUID) r.get("academy_id"), titleCase(email), email, reason, notes, requestId, "Requested in the academy app");
    }

    @Transactional
    public UUID create(UUID academyId, String name, String email, String reason, String notes) {
        if (jdbc.queryForObject("SELECT count(*) FROM academies WHERE id = ? AND closed_at IS NULL", Integer.class, academyId) == 0) throw new BadRequestException("Choose an academy.");
        if (name == null || name.trim().length() < 2) throw new BadRequestException("Enter the new owner's name.");
        if (email == null || !EMAIL.matcher(email.trim()).matches()) throw new BadRequestException("Enter a valid email address for the new owner.");
        if (reason == null || reason.isBlank()) throw new BadRequestException("Choose a reason.");
        if (jdbc.queryForObject("SELECT count(*) FROM hq_transfers WHERE academy_id = ? AND step IN ('REVIEW', 'OTP')", Integer.class, academyId) > 0) {
            throw new ConflictException("This academy already has a transfer in progress.");
        }
        return insert(academyId, name.trim(), email.trim(), reason.trim(), notes == null || notes.isBlank() ? null : notes.trim(), null, "Started by HQ");
    }

    private UUID insert(UUID academyId, String name, String email, String reason, String notes, UUID requestId, String firstLine) {
        UUID id = UUID.randomUUID();
        jdbc.update("INSERT INTO hq_transfers (id, academy_id, request_id, new_name, new_email, reason, notes) VALUES (?, ?, ?, ?, ?, ?, ?)",
                id, academyId, requestId, name, email, reason, notes);
        history(id, requestId == null ? actor() : "Owner of " + jdbc.queryForObject("SELECT name FROM academies WHERE id = ?", String.class, academyId), firstLine);
        audit.log("transfers", academyId, "Opened an ownership transfer to " + email);
        return id;
    }

    // ---------------------------------------------------------------- verification

    /** Sends a code to the current owner's phone and one to the new owner's email. */
    @Transactional
    public void start(UUID id, String newName, String newPhone) {
        var t = transfer(id);
        if (!"REVIEW".equals(t.get("step"))) throw new BadRequestException("Verification has already started.");
        if (newName == null || newName.trim().length() < 2) throw new BadRequestException("Enter the new owner's name.");
        String phone = newPhone == null ? "" : newPhone.replaceAll("\\s", "");
        if (!MOBILE.matcher(phone).matches()) throw new BadRequestException("Enter the new owner's 10-digit mobile number: it becomes their account's phone.");
        Map<String, String> owner = currentOwner((UUID) t.get("academy_id"));
        if (owner.get("phone") == null || !MOBILE.matcher(owner.get("phone")).matches()) {
            throw new BadRequestException("The current owner has no valid mobile number on file, so a code cannot be sent. Add it to the academy first.");
        }
        jdbc.update("UPDATE hq_transfers SET new_name = ?, new_phone = ?, previous_owner = ?, step = 'OTP' WHERE id = ?", newName.trim(), phone, owner.get("name"), id);
        send(id, t, "from");
        send(id, t, "to");
        history(id, actor(), "Started verification. Sent a code to each party");
        audit.log("transfers", (UUID) t.get("academy_id"), "Started verification for the transfer to " + t.get("new_email"));
    }

    private void send(UUID id, Map<String, Object> t, String who) {
        if ("from".equals(who)) {
            otp.requestOtp(currentOwner((UUID) t.get("academy_id")).get("phone"), OtpPurpose.OWNERSHIP_TRANSFER, id);
            jdbc.update("UPDATE hq_transfers SET sent_from_at = now() WHERE id = ?", id);
        } else {
            otp.requestOtpForEmail((String) t.get("new_email"), OtpPurpose.OWNERSHIP_TRANSFER, id);
            jdbc.update("UPDATE hq_transfers SET sent_to_at = now() WHERE id = ?", id);
        }
    }

    @Transactional
    public void resend(UUID id, String who) {
        var t = transfer(id);
        if (!"OTP".equals(t.get("step"))) throw new BadRequestException("This transfer is not waiting for codes.");
        Timestamp last = (Timestamp) t.get("from".equals(who) ? "sent_from_at" : "sent_to_at");
        if (last != null && Duration.between(last.toInstant(), Instant.now()).compareTo(RESEND_GAP) < 0) throw new BadRequestException("Wait a few seconds before resending.");
        if (Boolean.TRUE.equals(t.get("from".equals(who) ? "verified_from" : "verified_to"))) throw new BadRequestException("That person is already verified.");
        send(id, t, who);
    }

    /** Checks one party's code. When both are done the academy moves. Returns first sign-in details if a new account was made. */
    @Transactional
    public Map<String, Object> verify(UUID id, String who, String code) {
        var t = transfer(id);
        if (!"OTP".equals(t.get("step"))) throw new BadRequestException("This transfer is not waiting for codes.");
        if (code == null || !code.trim().matches("\\d{6}")) throw new BadRequestException("Enter the 6-digit code.");
        UUID context;
        if ("from".equals(who)) {
            context = otp.verifyOtp(currentOwner((UUID) t.get("academy_id")).get("phone"), code.trim(), OtpPurpose.OWNERSHIP_TRANSFER);
        } else {
            context = otp.verifyOtpForEmail((String) t.get("new_email"), code.trim(), OtpPurpose.OWNERSHIP_TRANSFER);
        }
        if (context != null && !context.equals(id)) throw new BadRequestException("That code belongs to a different transfer. Resend a new one.");
        jdbc.update("UPDATE hq_transfers SET " + ("from".equals(who) ? "verified_from" : "verified_to") + " = TRUE WHERE id = ?", id);
        history(id, "from".equals(who) ? "Current owner" : (String) t.get("new_name"), "from".equals(who) ? "Confirmed the handover with an OTP" : "Accepted the academy with an OTP");
        var now = transfer(id);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("done", false);
        if (Boolean.TRUE.equals(now.get("verified_from")) && Boolean.TRUE.equals(now.get("verified_to"))) {
            out.putAll(complete(id, now));
            out.put("done", true);
        }
        return out;
    }

    private Map<String, Object> complete(UUID id, Map<String, Object> t) {
        UUID academyId = (UUID) t.get("academy_id");
        String email = (String) t.get("new_email"), name = (String) t.get("new_name"), phone = (String) t.get("new_phone");
        String academyName = jdbc.queryForObject("SELECT name FROM academies WHERE id = ?", String.class, academyId);
        Map<String, String> old = currentOwner(academyId);

        Map<String, Object> out = new LinkedHashMap<>();
        UUID newUser;
        var existing = jdbc.queryForList("SELECT id FROM users WHERE lower(email) = lower(?)", UUID.class, email);
        if (existing.isEmpty()) {
            String username = uniqueUsername(email);
            UserWithTempPassword created = registration.createUserWithPassword(username, name, phone, email, Role.ACADEMY_ADMIN);
            newUser = created.user().getId();
            out.put("username", created.user().getUsername());
            out.put("password", created.temporaryPassword());
        } else {
            newUser = existing.get(0);
        }
        var mem = jdbc.queryForList("SELECT id, status FROM academy_memberships WHERE user_id = ? AND academy_id = ? AND role_type = 'ACADEMY_ADMIN'", newUser, academyId);
        if (mem.isEmpty()) {
            registration.createMembership(newUser, academyId, academyName, Role.ACADEMY_ADMIN, com.nest.app.identity.entity.MembershipStatus.ACTIVE, null);
        } else if (!"ACTIVE".equals(mem.get(0).get("status"))) {
            jdbc.update("UPDATE academy_memberships SET status = 'ACTIVE' WHERE id = ?", mem.get(0).get("id"));
        }
        // The previous owner steps down: their admin membership ends. Other admins are left alone.
        String oldEmail = old.get("email");
        jdbc.update("""
                UPDATE academy_memberships SET status = 'REVOKED'
                WHERE academy_id = ? AND role_type = 'ACADEMY_ADMIN' AND status = 'ACTIVE' AND user_id <> ?
                  AND user_id IN (SELECT id FROM users WHERE lower(email) = lower(?))""", academyId, newUser, oldEmail == null ? "" : oldEmail);
        jdbc.update("UPDATE academies SET owner_name = ?, owner_email = ?, owner_phone = ?, updated_at = now() WHERE id = ?", name, email, phone, academyId);
        jdbc.update("UPDATE hq_transfers SET step = 'DONE', done_at = now() WHERE id = ?", id);
        history(id, "System", "Both parties confirmed. Ownership moved from " + nz(old.get("name")) + " to " + name);
        audit.log("transfers", academyId, "Ownership of " + academyName + " transferred from " + nz(old.get("name")) + " to " + name + " (" + ref(((Number) t.get("seq")).longValue()) + "). Both owners confirmed with an OTP");
        if (t.get("request_id") != null) approvals.closeExternally((UUID) t.get("request_id"), "approved", "Completed in Academy transfer (" + ref(((Number) t.get("seq")).longValue()) + ")");
        return out;
    }

    private String uniqueUsername(String email) {
        String base = email.substring(0, email.indexOf('@')).toLowerCase().replaceAll("[^a-z0-9]", "");
        if (base.length() < 4) base = base + "owner";
        String candidate = base;
        int i = 1;
        while (jdbc.queryForObject("SELECT count(*) FROM users WHERE username = ?", Integer.class, candidate) > 0) candidate = base + (++i);
        return candidate;
    }

    @Transactional
    public void reject(UUID id, String reason) {
        var t = transfer(id);
        String step = (String) t.get("step");
        if (!"REVIEW".equals(step) && !"OTP".equals(step)) throw new BadRequestException("This transfer is already finished.");
        if (reason == null || reason.trim().length() < 3) throw new BadRequestException("A reason is required.");
        String why = ("OTP".equals(step) ? "Cancelled: " : "Rejected: ") + reason.trim();
        jdbc.update("UPDATE hq_transfers SET step = 'REJECTED', why = ? WHERE id = ?", why, id);
        history(id, actor(), why);
        audit.log("transfers", (UUID) t.get("academy_id"), "Ownership transfer to " + t.get("new_email") + " " + why.toLowerCase());
        if (t.get("request_id") != null) approvals.closeExternally((UUID) t.get("request_id"), "rejected", why);
    }

    private Map<String, Object> read(String s) {
        try {
            return json.readValue(s == null ? "{}" : s, new TypeReference<>() { });
        } catch (Exception e) {
            return new LinkedHashMap<>();
        }
    }
}
