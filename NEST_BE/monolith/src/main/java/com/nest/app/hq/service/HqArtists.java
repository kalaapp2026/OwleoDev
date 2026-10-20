package com.nest.app.hq.service;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.nest.app.hq.HqAudit;
import com.nest.app.notification.entity.NotificationModule;
import com.nest.app.notification.entity.NotificationType;
import com.nest.app.notification.service.NotificationService;
import com.nest.common.crypto.PiiEncryptor;
import com.nest.common.exception.BadRequestException;
import com.nest.common.exception.ConflictException;
import com.nest.common.exception.ResourceNotFoundException;
import com.nest.common.security.TenantContext;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

/**
 * Artist verification. A Guest who applies is checked by HQ (their linked profiles, a short
 * checklist, guardian consent if under 18) before being allowed to post as an Artist. After that
 * HQ moderates: reports can be upheld, each upheld report uses one of three chances, and the third
 * rejects the artist for good.
 *
 * <p>"Can post" is real: it is the account's ARTIST role. Approving with posting on makes the user
 * an ARTIST, and suspension or a posting switch-off returns them to GUEST. "Can host events" is
 * recorded for when artists can create events; today only academies can.
 */
@Service
public class HqArtists {

    static final List<String[]> CHECKLIST = List.of(
            new String[]{"name", "Name and photo match the artist", "1"},
            new String[]{"own", "Profile belongs to them (code in bio, link back or DM reply)", "1"},
            new String[]{"act", "Real posts and audience, not a fresh or bought account", "0"},
            new String[]{"art", "Art form matches what they posted", "0"},
            new String[]{"pol", "No policy flags or impersonation", "1"});
    private static final Set<String> CATEGORIES = Set.of("Copied or stolen work", "Impersonation", "Abusive or harmful content", "Misleading event", "Spam");
    private static final Set<String> REPORTERS = Set.of("User", "Academy", "Another artist", "Owleo staff");

    private final JdbcTemplate jdbc;
    private final HqAudit audit;
    private final ObjectMapper json;
    private final PiiEncryptor encryptor;
    private final NotificationService notifications;

    public HqArtists(JdbcTemplate jdbc, HqAudit audit, ObjectMapper json, PiiEncryptor encryptor, NotificationService notifications) {
        this.jdbc = jdbc;
        this.audit = audit;
        this.json = json;
        this.encryptor = encryptor;
        this.notifications = notifications;
    }

    private static String ref(long seq) {
        return "V-" + (309 + seq);
    }

    private static boolean open(String status) {
        return "PENDING".equals(status) || "INFO".equals(status);
    }

    private boolean minor(Object dobEnc) {
        if (dobEnc == null || dobEnc.toString().isBlank()) return false;
        try {
            return LocalDate.parse(encryptor.decrypt(dobEnc.toString())).isAfter(LocalDate.now().minusYears(18));
        } catch (Exception e) {
            return false;
        }
    }

    private List<Map<String, Object>> profiles(Object raw) {
        try {
            return json.readValue(raw == null ? "[]" : raw.toString(), new TypeReference<>() { });
        } catch (Exception e) {
            return new ArrayList<>();
        }
    }

    private Map<String, Boolean> checklist(Object raw) {
        try {
            return json.readValue(raw == null ? "{}" : raw.toString(), new TypeReference<>() { });
        } catch (Exception e) {
            return new LinkedHashMap<>();
        }
    }

    private String write(Object o) {
        try {
            return json.writeValueAsString(o);
        } catch (Exception e) {
            throw new IllegalStateException(e);
        }
    }

    // ---------------------------------------------------------------- reading

    private static final String BASE = """
            SELECT a.id, a.seq, a.user_id, a.status, a.art_form, a.city, a.bio, a.profiles, a.checklist, a.guardian_ok, a.can_post, a.can_events,
                   a.strikes, a.note, a.created_at, u.full_name, u.dob, u.username,
                   GREATEST(0, (current_date - a.created_at::date)) AS days,
                   (SELECT count(*) FROM hq_artist_reports r WHERE r.application_id = a.id AND r.status = 'open') AS open_reports
            FROM artist_applications a JOIN users u ON u.id = a.user_id""";

    public Map<String, Object> list(String f, String q) {
        var rows = jdbc.queryForList(BASE + " ORDER BY a.created_at");
        int pend = 0, app = 0, rp = 0, sus = 0, ban = 0, rej = 0;
        List<Map<String, Object>> shown = new ArrayList<>();
        String needle = q == null ? "" : q.trim().toLowerCase();
        for (var r : rows) {
            String st = (String) r.get("status");
            int reports = ((Number) r.get("open_reports")).intValue();
            switch (st) {
                case "PENDING", "INFO" -> pend++;
                case "APPROVED" -> { app++; rp += reports; }
                case "SUSPENDED" -> sus++;
                case "BANNED" -> ban++;
                case "REJECTED" -> rej++;
                default -> { }
            }
            boolean match = switch (f == null ? "pending" : f) {
                case "pending" -> open(st);
                case "approved" -> "APPROVED".equals(st);
                case "suspended" -> "SUSPENDED".equals(st);
                case "closed" -> "REJECTED".equals(st) || "BANNED".equals(st);
                default -> true;
            };
            if (!match) continue;
            Map<String, Object> m = card(r);
            if (!needle.isEmpty() && !(m.get("name") + " " + m.get("form") + " " + m.get("city") + " " + m.get("ref")).toLowerCase().contains(needle)) continue;
            shown.add(m);
        }
        // Open requests oldest first; everything else newest first.
        if ("pending".equals(f) || f == null) {
            // already oldest first from the query
        } else {
            java.util.Collections.reverse(shown);
        }
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("items", shown);
        out.put("pending", pend);
        out.put("approved", app);
        out.put("openReports", rp);
        out.put("suspended", sus);
        out.put("banned", ban);
        out.put("rejected", rej);
        return out;
    }

    private Map<String, Object> card(Map<String, Object> r) {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("id", r.get("id"));
        m.put("ref", ref(((Number) r.get("seq")).longValue()));
        m.put("name", r.get("full_name"));
        m.put("form", r.get("art_form") == null ? "Artist" : r.get("art_form"));
        m.put("city", r.get("city") == null ? "" : r.get("city"));
        m.put("status", ((String) r.get("status")).toLowerCase());
        m.put("minor", minor(r.get("dob")));
        m.put("platforms", profiles(r.get("profiles")).stream().map(p -> p.get("pl")).toList());
        m.put("openReports", r.get("open_reports"));
        m.put("strikes", r.get("strikes"));
        m.put("days", r.get("days"));
        return m;
    }

    public Map<String, Object> counts() {
        Map<String, Object> l = list("all", null);
        return Map.of("todo", ((Number) l.get("pending")).intValue() + ((Number) l.get("openReports")).intValue());
    }

    private Map<String, Object> row(UUID id) {
        var rows = jdbc.queryForList(BASE + " WHERE a.id = ?", id);
        if (rows.isEmpty()) throw new ResourceNotFoundException("Request not found");
        return rows.get(0);
    }

    public Map<String, Object> detail(UUID id) {
        var r = row(id);
        Map<String, Object> m = card(r);
        m.put("bio", r.get("bio"));
        m.put("profiles", profiles(r.get("profiles")));
        Map<String, Boolean> ck = checklist(r.get("checklist"));
        List<Map<String, Object>> items = new ArrayList<>();
        for (String[] c : CHECKLIST) {
            items.add(Map.of("key", c[0], "label", c[1], "required", "1".equals(c[2]), "done", Boolean.TRUE.equals(ck.get(c[0]))));
        }
        m.put("checklist", items);
        m.put("guardian", r.get("guardian_ok"));
        m.put("canPost", r.get("can_post"));
        m.put("canEvents", r.get("can_events"));
        m.put("note", r.get("note"));
        m.put("reports", jdbc.queryForList("""
                SELECT id, 'RP-' || (96 + seq) AS ref, reported_by AS "by", reporter_role AS role, category AS cat, details AS x, status AS st, decision_note AS note, created_at AS at
                FROM hq_artist_reports WHERE application_id = ? ORDER BY created_at DESC""", id));
        m.put("log", jdbc.queryForList("SELECT actor_name AS who, text AS x, at FROM hq_artist_log WHERE application_id = ? ORDER BY at DESC", id));
        m.put("categories", CATEGORIES.stream().sorted().toList());
        m.put("reporters", List.of("User", "Academy", "Another artist", "Owleo staff"));
        return m;
    }

    // ---------------------------------------------------------------- the review

    private String actor() {
        UUID a = TenantContext.currentUserIdOrNull();
        var n = a == null ? List.<String>of() : jdbc.queryForList("SELECT full_name FROM users WHERE id = ?", String.class, a);
        return n.isEmpty() ? "Owleo staff" : n.get(0);
    }

    private void log(UUID id, String text) {
        jdbc.update("INSERT INTO hq_artist_log (application_id, actor_name, text) VALUES (?, ?, ?)", id, actor(), text);
    }

    private void tell(Map<String, Object> r, String title, String body) {
        notifications.notify((UUID) r.get("user_id"), NotificationModule.SOCIAL, NotificationType.ADMIN_BROADCAST, title, body, null);
    }

    private void requireOpen(Map<String, Object> r) {
        if (!open((String) r.get("status"))) throw new BadRequestException("This request is already decided.");
    }

    @Transactional
    public void setCheck(UUID id, String key, boolean done) {
        var r = row(id);
        requireOpen(r);
        if (CHECKLIST.stream().noneMatch(c -> c[0].equals(key))) throw new BadRequestException("Unknown checklist item.");
        Map<String, Boolean> ck = checklist(r.get("checklist"));
        ck.put(key, done);
        jdbc.update("UPDATE artist_applications SET checklist = ? WHERE id = ?", write(ck), id);
    }

    @Transactional
    public void setGuardian(UUID id, boolean ok) {
        requireOpen(row(id));
        jdbc.update("UPDATE artist_applications SET guardian_ok = ? WHERE id = ?", ok, id);
    }

    /** Marks one linked profile as confirmed (with how), as not matching (with why), or back to unchecked. */
    @Transactional
    public void setProfile(UUID id, int index, String state, String method, String note) {
        var r = row(id);
        requireOpen(r);
        List<Map<String, Object>> ps = profiles(r.get("profiles"));
        if (index < 0 || index >= ps.size()) throw new BadRequestException("Unknown profile.");
        var p = ps.get(index);
        if (state == null) throw new BadRequestException("Unknown state.");
        switch (state) {
            case "ok" -> {
                if (method == null || !Set.of("Code in bio", "Link back", "DM reply").contains(method)) throw new BadRequestException("Choose how it was confirmed.");
                p.put("s", "ok");
                p.put("m", method);
                p.remove("note");
            }
            case "bad" -> {
                if (note == null || note.isBlank()) throw new BadRequestException("Say why it does not match.");
                p.put("s", "bad");
                p.put("m", "Not yet");
                p.put("note", note.trim());
            }
            case "pending" -> {
                p.put("s", "pending");
                p.put("m", "Not yet");
                p.remove("note");
            }
            default -> throw new BadRequestException("Unknown state.");
        }
        jdbc.update("UPDATE artist_applications SET profiles = ? WHERE id = ?", write(ps), id);
        log(id, ("ok".equals(state) ? "Confirmed " : "bad".equals(state) ? "Flagged " : "Reset ") + p.get("pl") + " profile " + p.get("h"));
    }

    @Transactional
    public void approve(UUID id, boolean post, boolean events) {
        var r = row(id);
        requireOpen(r);
        Map<String, Boolean> ck = checklist(r.get("checklist"));
        for (String[] c : CHECKLIST) {
            if ("1".equals(c[2]) && !Boolean.TRUE.equals(ck.get(c[0]))) throw new BadRequestException("Tick the starred checklist items first.");
        }
        if (minor(r.get("dob")) && !Boolean.TRUE.equals(r.get("guardian_ok"))) throw new BadRequestException("Guardian consent is needed: this artist is under 18.");
        if (profiles(r.get("profiles")).stream().noneMatch(p -> "ok".equals(p.get("s")))) throw new BadRequestException("Confirm at least one linked profile as theirs.");
        jdbc.update("UPDATE artist_applications SET status = 'APPROVED', can_post = ?, can_events = ?, decided_by = ?, decided_at = now(), note = NULL WHERE id = ?",
                post, events, TenantContext.currentUserIdOrNull(), id);
        setRole((UUID) r.get("user_id"), post);
        log(id, "Approved." + (post ? " Can post in Social." : "") + (events ? " Can host events." : "") + (!post && !events ? " No access switched on yet." : ""));
        audit.log("artists", "Approved artist " + r.get("full_name") + " (" + ref(((Number) r.get("seq")).longValue()) + ")");
        tell(r, "You're now an Artist!", post ? "Your application was approved - you can post to the feed now." : "Your application was approved.");
    }

    @Transactional
    public void reject(UUID id, String note) {
        var r = row(id);
        requireOpen(r);
        if (note == null || note.trim().length() < 3) throw new BadRequestException("Give a reason: the artist sees it.");
        jdbc.update("UPDATE artist_applications SET status = 'REJECTED', decided_by = ?, decided_at = now(), note = ? WHERE id = ?", TenantContext.currentUserIdOrNull(), note.trim(), id);
        log(id, "Rejected: " + note.trim());
        audit.log("artists", "Rejected artist request of " + r.get("full_name"));
        tell(r, "Artist application update", "Your application wasn't approved this time: " + note.trim());
    }

    @Transactional
    public void askMore(UUID id, String note) {
        var r = row(id);
        requireOpen(r);
        if (note == null || note.trim().length() < 3) throw new BadRequestException("Say what is needed.");
        jdbc.update("UPDATE artist_applications SET status = 'INFO', note = ? WHERE id = ?", note.trim(), id);
        log(id, "Asked: " + note.trim());
        tell(r, "More needed for your artist application", note.trim());
    }

    @Transactional
    public void reopen(UUID id) {
        var r = row(id);
        if (!"REJECTED".equals(r.get("status"))) throw new BadRequestException("Only a rejected request can be reopened.");
        jdbc.update("UPDATE artist_applications SET status = 'PENDING', note = NULL WHERE id = ?", id);
        log(id, "Reopened for review.");
    }

    // ---------------------------------------------------------------- access and moderation

    @Transactional
    public void setPermission(UUID id, String which, boolean on) {
        var r = row(id);
        if (!"APPROVED".equals(r.get("status"))) throw new BadRequestException("Only an approved artist has access to switch.");
        if ("post".equals(which)) {
            jdbc.update("UPDATE artist_applications SET can_post = ? WHERE id = ?", on, id);
            setRole((UUID) r.get("user_id"), on);
        } else if ("events".equals(which)) {
            jdbc.update("UPDATE artist_applications SET can_events = ? WHERE id = ?", on, id);
        } else {
            throw new BadRequestException("Unknown permission.");
        }
        log(id, (on ? "Switched on " : "Switched off ") + ("post".equals(which) ? "posting in Social" : "hosting events"));
        audit.log("artists", (on ? "Allowed " : "Stopped ") + r.get("full_name") + ("post".equals(which) ? " posting" : " hosting events"));
    }

    /** Posting is the ARTIST role: on makes a Guest an Artist, off returns them to Guest. */
    private void setRole(UUID userId, boolean artist) {
        if (artist) {
            jdbc.update("UPDATE users SET role_type = 'ARTIST', updated_at = now() WHERE id = ? AND role_type = 'GUEST'", userId);
        } else {
            jdbc.update("UPDATE users SET role_type = 'GUEST', updated_at = now() WHERE id = ? AND role_type = 'ARTIST'", userId);
        }
    }

    @Transactional
    public void logReport(UUID id, String by, String role, String category, String details) {
        var r = row(id);
        if ("REJECTED".equals(r.get("status"))) throw new BadRequestException("This artist was rejected, so there is nothing to report on.");
        if (by == null || by.trim().length() < 2) throw new BadRequestException("Enter who reported it.");
        if (role == null || !REPORTERS.contains(role)) throw new BadRequestException("Choose who reported it.");
        if (category == null || !CATEGORIES.contains(category)) throw new BadRequestException("Choose a reason.");
        if (details == null || details.trim().length() < 5) throw new BadRequestException("Describe the problem.");
        jdbc.update("INSERT INTO hq_artist_reports (application_id, reported_by, reporter_role, category, details) VALUES (?, ?, ?, ?, ?)",
                id, by.trim(), role, category, details.trim());
        log(id, "Report logged: " + category);
        audit.log("artists", "Logged a report on " + r.get("full_name") + ": " + category);
    }

    private Map<String, Object> report(UUID reportId, UUID appId) {
        var rows = jdbc.queryForList("SELECT * FROM hq_artist_reports WHERE id = ? AND application_id = ?", reportId, appId);
        if (rows.isEmpty()) throw new ResourceNotFoundException("Report not found");
        if (!"open".equals(rows.get(0).get("status"))) throw new ConflictException("This report was already decided.");
        return rows.get(0);
    }

    @Transactional
    public void dismissReport(UUID id, UUID reportId, String note) {
        var r = row(id);
        report(reportId, id);
        jdbc.update("UPDATE hq_artist_reports SET status = 'dismissed', decision_note = ? WHERE id = ?", note == null ? null : note.trim(), reportId);
        log(id, "Report dismissed." + (note == null || note.isBlank() ? "" : " " + note.trim()));
        audit.log("artists", "Dismissed a report on " + r.get("full_name"));
    }

    /** Upholding uses a chance: suspends, or rejects for good on the third. */
    @Transactional
    public String upholdReport(UUID id, UUID reportId, String note) {
        var r = row(id);
        var rep = report(reportId, id);
        if (!"APPROVED".equals(r.get("status"))) throw new BadRequestException("Only an approved artist can be moderated.");
        if (note == null || note.trim().length() < 3) throw new BadRequestException("Give a reason.");
        jdbc.update("UPDATE hq_artist_reports SET status = 'upheld', decision_note = ? WHERE id = ?", note.trim(), reportId);
        return strike(id, r, "Report upheld: " + rep.get("category") + ".");
    }

    @Transactional
    public String suspend(UUID id, String note) {
        var r = row(id);
        if (!"APPROVED".equals(r.get("status"))) throw new BadRequestException("Only an approved artist can be suspended.");
        if (note == null || note.trim().length() < 3) throw new BadRequestException("Give a reason.");
        return strike(id, r, "Suspended: " + note.trim() + ".");
    }

    private String strike(UUID id, Map<String, Object> r, String msg) {
        int strikes = ((Number) r.get("strikes")).intValue() + 1;
        boolean banned = strikes >= 3;
        jdbc.update("""
                UPDATE artist_applications SET strikes = ?, status = ?, prev_post = COALESCE(CASE WHEN status = 'APPROVED' THEN can_post END, prev_post),
                       prev_events = COALESCE(CASE WHEN status = 'APPROVED' THEN can_events END, prev_events), can_post = FALSE, can_events = FALSE WHERE id = ?""",
                strikes, banned ? "BANNED" : "SUSPENDED", id);
        setRole((UUID) r.get("user_id"), false);
        String name = (String) r.get("full_name");
        String result;
        if (banned) {
            log(id, msg + " Third chance used. Rejected for good, no access.");
            audit.log("artists", "Rejected " + name + " for good (" + ref(((Number) r.get("seq")).longValue()) + ")");
            result = "Third chance used. " + name.split(" ")[0] + " is rejected for good.";
            tell(r, "Artist access withdrawn", "Your artist access has been withdrawn and you cannot apply again.");
        } else {
            log(id, msg + " Suspended. Chance " + strikes + " of 3 used.");
            audit.log("artists", "Suspended " + name + " (" + ref(((Number) r.get("seq")).longValue()) + "), chance " + strikes + " of 3");
            result = "Suspended. Chance " + strikes + " of 3 used.";
            tell(r, "Artist access paused", "Your posting is paused after a report. Contact Owleo support if you want to talk about it.");
        }
        return result;
    }

    @Transactional
    public void reinstate(UUID id) {
        var r = row(id);
        if (!"SUSPENDED".equals(r.get("status"))) throw new BadRequestException("Only a suspended artist can be reinstated.");
        boolean post = !Boolean.FALSE.equals(r.get("prev_post")), events = !Boolean.FALSE.equals(r.get("prev_events"));
        jdbc.update("UPDATE artist_applications SET status = 'APPROVED', can_post = ?, can_events = ? WHERE id = ?", post, events, id);
        setRole((UUID) r.get("user_id"), post);
        log(id, "Reinstated after a warning.");
        audit.log("artists", "Reinstated " + r.get("full_name"));
        tell(r, "Artist access restored", "Your artist access is back as before.");
    }

    @Transactional
    public void ban(UUID id, String note) {
        var r = row(id);
        if (!"SUSPENDED".equals(r.get("status"))) throw new BadRequestException("Only a suspended artist can be rejected for good.");
        if (note == null || note.trim().length() < 3) throw new BadRequestException("Give a reason.");
        jdbc.update("UPDATE artist_applications SET status = 'BANNED', can_post = FALSE, can_events = FALSE WHERE id = ?", id);
        log(id, "Rejected for good: " + note.trim());
        audit.log("artists", "Rejected " + r.get("full_name") + " for good");
        tell(r, "Artist access withdrawn", "Your artist access has been withdrawn and you cannot apply again.");
    }

    /** Adds or changes the details HQ learned from the applicant (art form, city, bio, a linked profile). */
    @Transactional
    public void editDetails(UUID id, Map<String, Object> b) {
        var r = row(id);
        requireOpen(r);
        String form = str(b, "form"), city = str(b, "city"), bio = str(b, "bio");
        List<Map<String, Object>> ps = profiles(r.get("profiles"));
        if (b.get("addProfile") instanceof Map<?, ?> p) {
            String pl = String.valueOf(p.get("pl")), h = String.valueOf(p.get("h")).trim();
            if (!Set.of("instagram", "youtube", "facebook", "x", "spotify", "website").contains(pl)) throw new BadRequestException("Choose a platform.");
            if (h.length() < 2 || "null".equals(h)) throw new BadRequestException("Enter the handle or link.");
            if (ps.size() >= 6) throw new BadRequestException("Six profiles is the limit.");
            Map<String, Object> np = new LinkedHashMap<>();
            np.put("pl", pl);
            np.put("h", h);
            np.put("f", p.get("f") == null ? "" : String.valueOf(p.get("f")).trim());
            np.put("s", "pending");
            np.put("m", "Not yet");
            ps.add(np);
        }
        jdbc.update("UPDATE artist_applications SET art_form = ?, city = ?, bio = ?, profiles = ? WHERE id = ?",
                form.isEmpty() ? null : form, city.isEmpty() ? null : city, bio.isEmpty() ? null : (bio.length() > 500 ? bio.substring(0, 500) : bio), write(ps), id);
    }

    private static String str(Map<String, Object> b, String k) {
        Object v = b.get(k);
        return v == null ? "" : v.toString().trim();
    }
}
