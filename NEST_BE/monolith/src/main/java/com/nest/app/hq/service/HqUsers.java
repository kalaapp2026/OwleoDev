package com.nest.app.hq.service;

import com.nest.app.hq.HqAccess;
import com.nest.app.hq.HqAudit;
import com.nest.common.crypto.PiiEncryptor;
import com.nest.common.crypto.PiiHasher;
import com.nest.common.exception.BadRequestException;
import com.nest.common.exception.ResourceNotFoundException;
import com.nest.common.security.TenantContext;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.sql.Timestamp;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.regex.Pattern;
import java.util.stream.Collectors;

/**
 * Every person on the platform, across academies: search, the profile fields HQ requires, who is
 * missing them, contact reveal (always logged), edits, and activation.
 *
 * <p>Contact details stay masked in every response. They are only returned by {@link #reveal}, which
 * writes an audit line each time, and by {@link #editable}, which is the edit form's source and is
 * logged the same way.
 */
@Service
public class HqUsers {

    private static final Pattern EMAIL = Pattern.compile("^\\S+@\\S+\\.\\S+$");
    private static final Pattern MOBILE = Pattern.compile("^[6-9]\\d{9}$");
    private static final Pattern DATE = Pattern.compile("^\\d{4}-\\d{2}-\\d{2}$");

    private final JdbcTemplate jdbc;
    private final HqAudit audit;
    private final HqAccess access;
    private final PiiEncryptor encryptor;
    private final PiiHasher hasher;

    public HqUsers(JdbcTemplate jdbc, HqAudit audit, HqAccess access, PiiEncryptor encryptor, PiiHasher hasher) {
        this.jdbc = jdbc;
        this.audit = audit;
        this.access = access;
        this.encryptor = encryptor;
        this.hasher = hasher;
    }

    // ---------------------------------------------------------------- required fields

    public List<Map<String, Object>> requiredFields() {
        return jdbc.queryForList("SELECT field AS key, label, required AS \"on\" FROM hq_required_fields ORDER BY position");
    }

    /** The required field keys and their labels, in display order. */
    private Map<String, String> requiredLabels() {
        Map<String, String> out = new LinkedHashMap<>();
        for (var r : jdbc.queryForList("SELECT field, label FROM hq_required_fields WHERE required ORDER BY position")) {
            out.put((String) r.get("field"), (String) r.get("label"));
        }
        return out;
    }

    // ---------------------------------------------------------------- the people list

    private static final String POPULATION = """
            SELECT u.id, u.full_name, u.status, u.created_at, pm.role_type, pm.academy_id, a.name AS academy_name,
                   (u.email IS NULL OR u.email = '') AS no_email,
                   (u.address IS NULL OR u.address = '') AS no_addr,
                   u.dob,
                   (u.emergency_contact IS NULL OR u.emergency_contact = '') AS no_emer,
                   (u.guardian_name IS NULL OR u.guardian_name = '') AS no_guard,
                   (COALESCE(NULLIF(u.photo_url, ''), NULLIF(u.profile_image_url, '')) IS NULL) AS no_photo,
                   (SELECT count(DISTINCT m2.academy_id) FROM academy_memberships m2
                     WHERE m2.user_id = u.id AND m2.status IN ('ACTIVE', 'REVOKED')) AS academies
            FROM users u
            JOIN LATERAL (SELECT m.academy_id, m.role_type FROM academy_memberships m
                           WHERE m.user_id = u.id AND m.status IN ('ACTIVE', 'REVOKED')
                           ORDER BY (m.status = 'ACTIVE') DESC, m.created_at LIMIT 1) pm ON TRUE
            JOIN academies a ON a.id = pm.academy_id
            WHERE u.role_type <> 'SUPER_ADMIN'""";

    private static String ref(UUID id) {
        return "OW" + id.toString().replace("-", "").substring(0, 6).toUpperCase();
    }

    private static String roleLabel(String r) {
        return switch (r) {
            case "STUDENT" -> "Student";
            case "TRAINER" -> "Trainer";
            case "ACADEMY_ADMIN" -> "Admin";
            default -> r;
        };
    }

    private boolean isMinor(String dobEnc) {
        if (dobEnc == null || dobEnc.isBlank()) return false;
        try {
            return LocalDate.parse(encryptor.decrypt(dobEnc)).isAfter(LocalDate.now().minusYears(18));
        } catch (Exception e) {
            return false;
        }
    }

    /** Labels of the required fields this person has not filled in. */
    private List<String> missing(Map<String, Object> r, Map<String, String> req) {
        List<String> out = new ArrayList<>();
        req.forEach((k, label) -> {
            boolean gap = switch (k) {
                case "email" -> (Boolean) r.get("no_email");
                case "addr" -> (Boolean) r.get("no_addr");
                case "dob" -> r.get("dob") == null || r.get("dob").toString().isBlank();
                case "emer" -> (Boolean) r.get("no_emer");
                case "guard" -> "STUDENT".equals(r.get("role_type")) && (Boolean) r.get("no_guard") && isMinor((String) r.get("dob"));
                case "photo" -> (Boolean) r.get("no_photo");
                default -> false;
            };
            if (gap) out.add(label);
        });
        return out;
    }

    /**
     * One page of people. [academy] / [course] / [batch] / [trainer] narrow the search; [flt] is the
     * quick chip (all, miss, multi, inact). The counts always describe the whole platform, as the
     * chips do in the console.
     */
    public Map<String, Object> list(String q, UUID academy, String course, String batch, UUID trainer, String status, String flt, int limit, int offset) {
        Map<String, String> req = requiredLabels();
        var population = jdbc.queryForList(POPULATION);
        Set<UUID> matched = matching(q, academy, course, batch, trainer, status);

        int miss = 0, multi = 0, inactive = 0, active = 0;
        Map<String, Integer> byField = new HashMap<>();
        List<Map<String, Object>> shown = new ArrayList<>();
        for (var r : population) {
            List<String> gaps = missing(r, req);
            boolean off = !"ACTIVE".equals(r.get("status"));
            int n = ((Number) r.get("academies")).intValue();
            if (!gaps.isEmpty()) miss++;
            if (n > 1) multi++;
            if (off) inactive++; else active++;
            gaps.forEach(g -> byField.merge(g, 1, Integer::sum));
            if (matched != null && !matched.contains((UUID) r.get("id"))) continue;
            if ("miss".equals(flt) && gaps.isEmpty()) continue;
            if ("multi".equals(flt) && n < 2) continue;
            if ("inact".equals(flt) && !off) continue;
            Map<String, Object> m = new LinkedHashMap<>();
            UUID id = (UUID) r.get("id");
            m.put("id", id);
            m.put("ref", ref(id));
            m.put("name", r.get("full_name"));
            m.put("role", roleLabel((String) r.get("role_type")));
            m.put("status", off ? "Inactive" : "Active");
            m.put("academyId", r.get("academy_id"));
            m.put("academy", r.get("academy_name"));
            m.put("academies", n);
            m.put("missing", gaps.size());
            shown.add(m);
        }
        shown.sort(Comparator.comparing(m -> ((String) m.get("name")).toLowerCase()));
        int total = shown.size();
        List<Map<String, Object>> page = shown.subList(Math.min(offset, total), Math.min(offset + limit, total));
        attachCourses(page);

        int profiles = population.size();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("total", total);
        out.put("items", page);
        out.put("counts", Map.of("all", profiles, "miss", miss, "multi", multi, "inact", inactive));
        out.put("profiles", profiles);
        out.put("active", active);
        out.put("inactive", inactive);
        out.put("missing", miss);
        out.put("multi", multi);
        out.put("missingTop", byField.entrySet().stream().sorted((a, b) -> b.getValue() - a.getValue()).limit(4)
                .map(e -> Map.<String, Object>of("label", e.getKey(), "n", e.getValue())).toList());
        out.put("academiesWithUsers", population.stream().map(r -> r.get("academy_id")).distinct().count());
        return out;
    }

    /** Ids matching the narrowing filters, or null when none were given. */
    private Set<UUID> matching(String q, UUID academy, String course, String batch, UUID trainer, String status) {
        List<String> where = new ArrayList<>();
        List<Object> args = new ArrayList<>();
        if (q != null && !q.isBlank()) {
            String t = q.trim().toLowerCase();
            String digits = t.replaceAll("\\D", "");
            String idPart = t.replaceFirst("^ow", "").toUpperCase();
            where.add("(lower(u.full_name) LIKE ? OR upper(substr(replace(u.id::text, '-', ''), 1, 6)) LIKE ? OR u.phone_hash = ?)");
            args.add("%" + t + "%");
            args.add(idPart.isEmpty() ? "NOMATCH" : idPart + "%");
            args.add(digits.length() == 10 ? hasher.hash(digits) : "none");
        }
        if (academy != null) {
            where.add("EXISTS (SELECT 1 FROM academy_memberships m WHERE m.user_id = u.id AND m.academy_id = ? AND m.status IN ('ACTIVE', 'REVOKED'))");
            args.add(academy);
        }
        String pb = """
                (SELECT m.user_id, bm.batch_id FROM academy_memberships m JOIN batch_members bm ON bm.membership_id = m.id
                 UNION SELECT m.user_id, bt.batch_id FROM academy_memberships m JOIN batch_trainers bt ON bt.trainer_membership_id = m.id)""";
        if (course != null && !course.isBlank()) {
            where.add("EXISTS (SELECT 1 FROM " + pb + " pb JOIN batches b ON b.id = pb.batch_id JOIN courses c ON c.id = b.course_id WHERE pb.user_id = u.id AND c.name = ?)");
            args.add(course);
        }
        if (batch != null && !batch.isBlank()) {
            where.add("EXISTS (SELECT 1 FROM " + pb + " pb JOIN batches b ON b.id = pb.batch_id WHERE pb.user_id = u.id AND b.name = ?)");
            args.add(batch);
        }
        if (trainer != null) {
            where.add("EXISTS (SELECT 1 FROM academy_memberships m JOIN batch_members bm ON bm.membership_id = m.id JOIN batch_trainers bt ON bt.batch_id = bm.batch_id WHERE m.user_id = u.id AND bt.trainer_membership_id = ?)");
            args.add(trainer);
        }
        if ("Active".equalsIgnoreCase(status)) where.add("u.status = 'ACTIVE'");
        if ("Inactive".equalsIgnoreCase(status)) where.add("u.status <> 'ACTIVE'");
        if (where.isEmpty()) return null;
        return new HashSet<>(jdbc.queryForList("SELECT u.id FROM users u WHERE u.role_type <> 'SUPER_ADMIN' AND " + String.join(" AND ", where), UUID.class, args.toArray()));
    }

    /** The first course each listed person is in, for the card's tag. */
    private void attachCourses(List<Map<String, Object>> page) {
        if (page.isEmpty()) return;
        String ids = page.stream().map(m -> "'" + m.get("id") + "'").collect(Collectors.joining(","));
        Map<UUID, String> first = new HashMap<>();
        for (var r : jdbc.queryForList("""
                SELECT DISTINCT ON (pb.user_id) pb.user_id, c.name
                FROM (SELECT m.user_id, bm.batch_id FROM academy_memberships m JOIN batch_members bm ON bm.membership_id = m.id
                      UNION SELECT m.user_id, bt.batch_id FROM academy_memberships m JOIN batch_trainers bt ON bt.trainer_membership_id = m.id) pb
                JOIN batches b ON b.id = pb.batch_id JOIN courses c ON c.id = b.course_id
                WHERE pb.user_id IN (""" + ids + ") ORDER BY pb.user_id, c.name")) {
            first.put((UUID) r.get("user_id"), (String) r.get("name"));
        }
        page.forEach(m -> m.put("course", first.get((UUID) m.get("id"))));
    }

    /** Choices for the filter panel: academies, plus courses, batches and trainers (narrowed to one academy when given). */
    public Map<String, Object> filters(UUID academy) {
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("academies", jdbc.queryForList("""
                SELECT DISTINCT a.id, a.name FROM academies a JOIN academy_memberships m ON m.academy_id = a.id ORDER BY a.name"""));
        String scope = academy == null ? "" : " AND c.academy_id = ?";
        Object[] args = academy == null ? new Object[0] : new Object[]{academy};
        out.put("courses", jdbc.queryForList("SELECT DISTINCT c.name FROM courses c WHERE TRUE" + scope + " ORDER BY c.name", String.class, args));
        out.put("batches", jdbc.queryForList("SELECT DISTINCT b.name FROM batches b JOIN courses c ON c.id = b.course_id WHERE TRUE" + scope + " ORDER BY b.name", String.class, args));
        out.put("trainers", academy == null ? List.of() : jdbc.queryForList("""
                SELECT m.id, u.full_name AS name FROM academy_memberships m JOIN users u ON u.id = m.user_id
                WHERE m.academy_id = ? AND m.role_type = 'TRAINER' AND m.status = 'ACTIVE' ORDER BY u.full_name""", academy));
        return out;
    }

    // ---------------------------------------------------------------- one person

    private static String maskPhone(String p) {
        if (p == null || p.length() < 6) return p;
        return p.substring(0, 2) + "••••••" + p.substring(p.length() - 2);
    }

    private static String maskEmail(String e) {
        int at = e.indexOf('@');
        if (at < 2) return e;
        return e.charAt(0) + "•••" + e.substring(at);
    }

    private Map<String, Object> user(UUID id) {
        var rows = jdbc.queryForList("SELECT * FROM users WHERE id = ? AND role_type <> 'SUPER_ADMIN'", id);
        if (rows.isEmpty()) throw new ResourceNotFoundException("Person not found");
        return rows.get(0);
    }

    private String dec(Object v) {
        return v == null || v.toString().isBlank() ? null : encryptor.decrypt(v.toString());
    }

    private Map<String, Object> contact(String masked, boolean present) {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("present", present);
        m.put("masked", masked);
        return m;
    }

    public Map<String, Object> detail(UUID id) {
        var u = user(id);
        Map<String, String> req = requiredLabels();
        Map<String, Object> out = new LinkedHashMap<>();
        String role = (String) u.get("role_type");
        out.put("id", id);
        out.put("ref", ref(id));
        out.put("name", u.get("full_name"));
        out.put("role", roleLabel(role));
        out.put("status", "ACTIVE".equals(u.get("status")) ? "Active" : "Inactive");
        out.put("access", switch (role) {
            case "STUDENT" -> "Student app";
            case "TRAINER" -> "Trainer app";
            default -> "Admin console";
        });
        out.put("joined", ((Timestamp) u.get("created_at")).toLocalDateTime().toLocalDate());

        String phone = dec(u.get("phone"));
        String email = (String) u.get("email");
        String emer = dec(u.get("emergency_contact"));
        String dob = dec(u.get("dob"));
        boolean minor = isMinor((String) u.get("dob"));
        Map<String, Object> f = new LinkedHashMap<>();
        f.put("mobile", contact(phone == null ? null : maskPhone(phone), phone != null));
        f.put("email", contact(email == null || email.isBlank() ? null : maskEmail(email), email != null && !email.isBlank()));
        f.put("emer", contact(emer == null ? null : maskPhone(emer), emer != null));
        f.put("addr", dec(u.get("address")));
        f.put("dob", dob);
        f.put("guard", u.get("guardian_name"));
        f.put("minor", minor);
        f.put("photo", u.get("photo_url") != null || u.get("profile_image_url") != null);
        out.put("fields", f);

        Map<String, Object> probe = new HashMap<>();
        probe.put("role_type", role);
        probe.put("no_email", email == null || email.isBlank());
        probe.put("no_addr", dec(u.get("address")) == null);
        probe.put("dob", u.get("dob"));
        probe.put("no_emer", emer == null);
        probe.put("no_guard", u.get("guardian_name") == null || u.get("guardian_name").toString().isBlank());
        probe.put("no_photo", u.get("photo_url") == null && u.get("profile_image_url") == null);
        out.put("missing", missing(probe, req));
        out.put("required", req);

        List<Map<String, Object>> maps = new ArrayList<>();
        for (var m : jdbc.queryForList("""
                SELECT m.id, m.academy_id, a.name AS academy, m.role_type, m.status FROM academy_memberships m
                JOIN academies a ON a.id = m.academy_id WHERE m.user_id = ? AND m.status IN ('ACTIVE', 'REVOKED') ORDER BY m.created_at""", id)) {
            Map<String, Object> x = new LinkedHashMap<>();
            x.put("academyId", m.get("academy_id"));
            x.put("academy", m.get("academy"));
            x.put("role", roleLabel((String) m.get("role_type")));
            x.put("status", "ACTIVE".equals(m.get("status")) ? "Active" : "Removed");
            x.put("batches", jdbc.queryForList("""
                    SELECT c.name AS course, b.name AS batch,
                           (SELECT string_agg(tu.full_name, ', ') FROM batch_trainers bt JOIN academy_memberships tm ON tm.id = bt.trainer_membership_id
                              JOIN users tu ON tu.id = tm.user_id WHERE bt.batch_id = b.id) AS trainer
                    FROM (SELECT bm.batch_id FROM batch_members bm WHERE bm.membership_id = ?
                          UNION SELECT bt.batch_id FROM batch_trainers bt WHERE bt.trainer_membership_id = ?) x
                    JOIN batches b ON b.id = x.batch_id JOIN courses c ON c.id = b.course_id ORDER BY c.name, b.name""", m.get("id"), m.get("id")));
            maps.add(x);
        }
        out.put("academies", maps);
        out.put("changes", jdbc.queryForList("""
                SELECT field AS f, from_value AS "from", to_value AS "to", actor_name AS by, at FROM hq_user_history
                WHERE user_id = ? AND kind = 'CHANGE' ORDER BY at DESC LIMIT 8""", id));
        out.put("statusHistory", jdbc.queryForList("""
                SELECT to_value AS s, reason AS why, actor_name AS by, at FROM hq_user_history
                WHERE user_id = ? AND kind = 'STATUS' ORDER BY at DESC""", id));
        return out;
    }

    /** Reveals one contact value. Every call leaves an audit line saying who looked at whose number. */
    @Transactional
    public String reveal(UUID id, String field) {
        var u = user(id);
        String value = switch (field) {
            case "mobile" -> dec(u.get("phone"));
            case "email" -> (String) u.get("email");
            case "emer" -> dec(u.get("emergency_contact"));
            default -> throw new BadRequestException("That field cannot be revealed.");
        };
        if (value == null || value.isBlank()) throw new BadRequestException("Nothing is on file for this field.");
        String label = switch (field) { case "mobile" -> "mobile number"; case "email" -> "email address"; default -> "emergency contact"; };
        audit.log("users", "Revealed the " + label + " of " + u.get("full_name") + " (" + ref(id) + ")");
        return value;
    }

    /** The edit form's values. Contains contact details, so it is logged like a reveal. */
    @Transactional
    public Map<String, Object> editable(UUID id) {
        access.requireWrite();
        var u = user(id);
        audit.log("users", "Opened the profile of " + u.get("full_name") + " (" + ref(id) + ") for editing");
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("name", u.get("full_name"));
        m.put("mobile", dec(u.get("phone")));
        m.put("email", u.get("email"));
        m.put("addr", dec(u.get("address")));
        m.put("dob", dec(u.get("dob")));
        m.put("emer", dec(u.get("emergency_contact")));
        m.put("guard", u.get("guardian_name"));
        m.put("minor", isMinor((String) u.get("dob")));
        return m;
    }

    private static String s(Map<String, Object> b, String k) {
        Object v = b.get(k);
        return v == null ? "" : v.toString().trim();
    }

    @Transactional
    public void update(UUID id, Map<String, Object> b) {
        var u = user(id);
        String name = s(b, "name"), mobile = s(b, "mobile").replaceAll("\\s", ""), email = s(b, "email");
        String addr = s(b, "addr"), dob = s(b, "dob"), emer = s(b, "emer").replaceAll("\\s", ""), guard = s(b, "guard");
        Map<String, String> req = requiredLabels();
        if (name.length() < 3) throw new BadRequestException("Enter the full name.");
        if (!MOBILE.matcher(mobile).matches()) throw new BadRequestException("Enter a valid 10-digit mobile number.");
        if (!email.isEmpty() && !EMAIL.matcher(email).matches()) throw new BadRequestException("Enter a valid email address.");
        if (!emer.isEmpty() && !MOBILE.matcher(emer).matches()) throw new BadRequestException("Enter the emergency contact as a 10-digit mobile number.");
        if (!dob.isEmpty()) {
            if (!DATE.matcher(dob).matches()) throw new BadRequestException("Enter the date of birth as a date.");
            try {
                if (LocalDate.parse(dob).isAfter(LocalDate.now())) throw new BadRequestException("The date of birth cannot be in the future.");
            } catch (java.time.DateTimeException e) {
                throw new BadRequestException("Enter a valid date of birth.");
            }
        }
        for (var e : Map.of("email", email, "addr", addr, "dob", dob, "emer", emer).entrySet()) {
            if (req.containsKey(e.getKey()) && e.getValue().isEmpty()) throw new BadRequestException(req.get(e.getKey()) + " is required.");
        }
        boolean minor = !dob.isEmpty() && LocalDate.parse(dob).isAfter(LocalDate.now().minusYears(18));
        if (minor && "STUDENT".equals(u.get("role_type")) && req.containsKey("guard") && guard.isEmpty()) throw new BadRequestException("Guardian details are required under 18.");

        String oldPhone = dec(u.get("phone"));
        change(id, "Name", (String) u.get("full_name"), name, false);
        change(id, "Mobile", oldPhone, mobile, true);
        change(id, "Email", (String) u.get("email"), email, true);
        change(id, "Address", dec(u.get("address")), addr, true);
        change(id, "Date of birth", dec(u.get("dob")), dob, false);
        change(id, "Emergency contact", dec(u.get("emergency_contact")), emer, true);
        change(id, "Guardian", (String) u.get("guardian_name"), guard, false);

        int sp = name.indexOf(' ');
        jdbc.update("""
                UPDATE users SET full_name = ?, first_name = ?, last_name = ?, phone = ?, phone_hash = ?, email = ?, address = ?, dob = ?,
                       emergency_contact = ?, guardian_name = ?, updated_at = now() WHERE id = ?""",
                name, sp < 0 ? name : name.substring(0, sp), sp < 0 ? null : name.substring(sp + 1).trim(),
                encryptor.encrypt(mobile), hasher.hash(mobile), email.isEmpty() ? null : email,
                addr.isEmpty() ? null : encryptor.encrypt(addr), dob.isEmpty() ? null : encryptor.encrypt(dob),
                emer.isEmpty() ? null : encryptor.encrypt(emer), guard.isEmpty() ? null : guard, id);
        audit.log("users", "Edited the profile of " + name + " (" + ref(id) + ")");
    }

    /** Records one field change. Private values are noted as updated, never copied into the history. */
    private void change(UUID id, String field, String from, String to, boolean private_) {
        String a = from == null ? "" : from, b = to == null ? "" : to;
        if (a.equals(b)) return;
        jdbc.update("INSERT INTO hq_user_history (user_id, kind, field, from_value, to_value, actor_name) VALUES (?, 'CHANGE', ?, ?, ?, ?)",
                id, field, private_ ? (a.isEmpty() ? "—" : "On file") : (a.isEmpty() ? "—" : a), private_ ? (b.isEmpty() ? "Removed" : "Updated") : (b.isEmpty() ? "—" : b), actorName());
    }

    private String actorName() {
        UUID actor = TenantContext.currentUserIdOrNull();
        if (actor == null) return "System";
        var n = jdbc.queryForList("SELECT full_name FROM users WHERE id = ?", String.class, actor);
        return n.isEmpty() ? "System" : n.get(0);
    }

    // ---------------------------------------------------------------- activation

    /**
     * Deactivating blocks sign-in (the login refuses INACTIVE accounts), ends every session, and removes
     * academy access. Reactivating gives it back. The profile and its history are always kept.
     */
    @Transactional
    public void setActive(UUID id, boolean active, String reason, String note) {
        var u = user(id);
        boolean now = "ACTIVE".equals(u.get("status"));
        if (now == active) throw new BadRequestException(active ? "This account is already active." : "This account is already inactive.");
        if (reason == null || reason.isBlank()) throw new BadRequestException("Choose a reason.");
        deactivateOrRestore(id, active);
        String why = note == null || note.isBlank() ? reason : reason + ": " + note.trim();
        jdbc.update("INSERT INTO hq_user_history (user_id, kind, to_value, reason, actor_name) VALUES (?, 'STATUS', ?, ?, ?)",
                id, active ? "Active" : "Inactive", why.length() > 200 ? why.substring(0, 200) : why, actorName());
        audit.log("users", (active ? "Reactivated account " : "Deactivated account ") + ref(id) + " (" + u.get("full_name") + "), reason: " + reason);
    }

    /** Shared with Exits: flips the account and, on deactivation, ends sessions. */
    void deactivateOrRestore(UUID id, boolean active) {
        jdbc.update("UPDATE users SET status = ?, updated_at = now() WHERE id = ?", active ? "ACTIVE" : "INACTIVE", id);
        if (active) {
            jdbc.update("UPDATE academy_memberships SET status = 'ACTIVE' WHERE user_id = ? AND status = 'REVOKED'", id);
        } else {
            jdbc.update("UPDATE academy_memberships SET status = 'REVOKED' WHERE user_id = ? AND status = 'ACTIVE'", id);
            jdbc.update("UPDATE refresh_tokens SET revoked = TRUE, revoked_at = now() WHERE user_id = ? AND NOT revoked", id);
        }
    }

    // ---------------------------------------------------------------- for other modules

    /** Every person (optionally one academy's), for the user report. */
    @SuppressWarnings("unchecked")
    public List<Map<String, Object>> listAll(UUID academy) {
        return (List<Map<String, Object>>) list(null, academy, null, null, null, null, "all", Integer.MAX_VALUE / 2, 0).get("items");
    }

    /** Short rows for people pickers and report exports: id, name, role, academy. */
    public List<Map<String, Object>> search(String q, int limit) {
        return (List<Map<String, Object>>) ((Map<String, Object>) list(q, null, null, null, null, null, "all", limit, 0)).get("items");
    }

    /** For each profile field, how many people lack it, whether or not it is currently required. */
    public Map<String, Integer> gapCounts() {
        Map<String, String> all = new LinkedHashMap<>();
        for (var r : jdbc.queryForList("SELECT field, label FROM hq_required_fields ORDER BY position")) {
            all.put((String) r.get("field"), (String) r.get("field"));
        }
        Map<String, Integer> out = new LinkedHashMap<>();
        all.keySet().forEach(k -> out.put(k, 0));
        for (var r : jdbc.queryForList(POPULATION)) {
            missing(r, all).forEach(k -> out.merge(k, 1, Integer::sum));
        }
        return out;
    }

    public String refOf(UUID id) {
        return ref(id);
    }

    public Map<String, Object> summary() {
        Map<String, Object> full = list(null, null, null, null, null, null, "all", 0, 0);
        full.remove("items");
        return full;
    }
}
