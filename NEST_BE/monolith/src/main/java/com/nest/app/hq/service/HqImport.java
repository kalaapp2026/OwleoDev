package com.nest.app.hq.service;

import com.nest.app.hq.HqAudit;
import com.nest.app.identity.entity.AcademyMembership;
import com.nest.app.identity.entity.MembershipStatus;
import com.nest.app.identity.service.IdentityRegistrationService;
import com.nest.app.identity.service.UserWithTempPassword;
import com.nest.common.crypto.PiiHasher;
import com.nest.common.exception.BadRequestException;
import com.nest.common.exception.ResourceNotFoundException;
import com.nest.common.security.Role;
import com.nest.common.security.TenantContext;
import jakarta.persistence.EntityManager;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.regex.Pattern;

/**
 * Adds many students to an academy from one file. The same rows are checked first (nothing is
 * written), then created on confirmation. Each student gets a real account, an academy membership
 * and, where the file names a course and batch that exist, a place in them. The temporary passwords
 * are returned once so HQ can hand them over.
 */
@Service
public class HqImport {

    static final int MAX_ROWS = 500;
    private static final Pattern EMAIL = Pattern.compile("^\\S+@\\S+\\.\\S+$");
    private static final Pattern MOBILE = Pattern.compile("^[6-9]\\d{9}$");

    private final JdbcTemplate jdbc;
    private final HqAudit audit;
    private final PiiHasher hasher;
    private final IdentityRegistrationService registration;
    private final EntityManager em;

    public HqImport(JdbcTemplate jdbc, HqAudit audit, PiiHasher hasher, IdentityRegistrationService registration, EntityManager em) {
        this.jdbc = jdbc;
        this.audit = audit;
        this.hasher = hasher;
        this.registration = registration;
        this.em = em;
    }

    private record Row(int line, String name, String mobile, String email, String course, String batch) {
    }

    @Transactional
    public Map<String, Object> run(UUID academyId, List<Map<String, Object>> raw, boolean commit) {
        var academy = jdbc.queryForList("SELECT name FROM academies WHERE id = ? AND closed_at IS NULL", academyId);
        if (academy.isEmpty()) throw new ResourceNotFoundException("Academy not found");
        String academyName = (String) academy.get(0).get("name");
        if (raw == null || raw.isEmpty()) throw new BadRequestException("The file has no rows.");
        if (raw.size() > MAX_ROWS) throw new BadRequestException("Import at most " + MAX_ROWS + " rows at a time.");

        // Courses and batches the academy actually has, by lower-cased name.
        Map<String, UUID> courses = new LinkedHashMap<>();
        Map<String, UUID> batches = new LinkedHashMap<>();   // "course|batch" -> batch id
        Map<UUID, BigDecimal> fees = new LinkedHashMap<>();
        for (var c : jdbc.queryForList("SELECT id, name, default_fee FROM courses WHERE academy_id = ? AND status = 'ACTIVE'", academyId)) {
            courses.put(((String) c.get("name")).toLowerCase(), (UUID) c.get("id"));
            fees.put((UUID) c.get("id"), c.get("default_fee") == null ? BigDecimal.ZERO : (BigDecimal) c.get("default_fee"));
        }
        for (var b : jdbc.queryForList("SELECT b.id, b.name, c.name AS course FROM batches b JOIN courses c ON c.id = b.course_id WHERE c.academy_id = ? AND b.status = 'ACTIVE'", academyId)) {
            batches.put(((String) b.get("course")).toLowerCase() + "|" + ((String) b.get("name")).toLowerCase(), (UUID) b.get("id"));
        }

        Set<String> seen = new HashSet<>();
        List<Row> ok = new ArrayList<>();
        List<Map<String, Object>> bad = new ArrayList<>();
        int line = 1;
        for (var r : raw) {
            line++;
            Row row = new Row(line, s(r, "name"), s(r, "mobile").replaceAll("\\s", ""), s(r, "email"), s(r, "course"), s(r, "batch"));
            List<String> why = new ArrayList<>();
            if (row.name().length() < 3) why.add("name is too short");
            if (!MOBILE.matcher(row.mobile()).matches()) why.add("mobile is not a valid 10-digit number");
            if (!row.email().isEmpty() && !EMAIL.matcher(row.email()).matches()) why.add("email is not valid");
            if (MOBILE.matcher(row.mobile()).matches()) {
                if (!seen.add(row.mobile())) why.add("mobile appears twice in this file");
                else if (jdbc.queryForObject("SELECT count(*) FROM users WHERE phone_hash = ?", Integer.class, hasher.hash(row.mobile())) > 0) why.add("mobile is already registered");
            }
            if (!row.email().isEmpty() && EMAIL.matcher(row.email()).matches()
                    && jdbc.queryForObject("SELECT count(*) FROM users WHERE lower(email) = lower(?)", Integer.class, row.email()) > 0) why.add("email already has an account");
            if (!row.course().isEmpty() && !courses.containsKey(row.course().toLowerCase())) why.add("this academy has no course called " + row.course());
            else if (!row.course().isEmpty() && !row.batch().isEmpty() && !batches.containsKey(row.course().toLowerCase() + "|" + row.batch().toLowerCase())) why.add("no batch " + row.batch() + " in " + row.course());
            else if (row.course().isEmpty() && !row.batch().isEmpty()) why.add("a batch needs a course");
            if (why.isEmpty()) {
                ok.add(row);
            } else {
                Map<String, Object> b = new LinkedHashMap<>();
                b.put("row", row.line());
                b.put("name", row.name());
                b.put("why", String.join(", ", why));
                bad.add(b);
            }
        }

        Map<String, Object> out = new LinkedHashMap<>();
        out.put("ready", ok.size());
        out.put("bad", bad);
        if (!commit) return out;
        if (ok.isEmpty()) throw new BadRequestException("There is nothing valid to import.");

        UUID by = TenantContext.currentUserIdOrNull();
        List<Map<String, Object>> credentials = new ArrayList<>();
        for (Row row : ok) {
            String username = uniqueUsername(row.name());
            UserWithTempPassword created = registration.createStudentWithPassword(username, row.name(), row.mobile(), row.email().isEmpty() ? null : row.email(), null, null, null, null, Role.STUDENT);
            AcademyMembership m = registration.createMembership(created.user().getId(), academyId, academyName, Role.STUDENT, MembershipStatus.ACTIVE, by);
            registration.setJoiningDate(m, null);
            if (!row.course().isEmpty()) {
                UUID course = courses.get(row.course().toLowerCase());
                registration.addCourseMap(m.getId(), Map.of(course, fees.get(course)));
                if (!row.batch().isEmpty()) {
                    em.flush();   // the membership must exist before a batch row can point at it
                    jdbc.update("INSERT INTO batch_members (id, batch_id, membership_id, joined_at) VALUES (?, ?, ?, now())", UUID.randomUUID(),
                            batches.get(row.course().toLowerCase() + "|" + row.batch().toLowerCase()), m.getId());
                }
            }
            Map<String, Object> c = new LinkedHashMap<>();
            c.put("name", row.name());
            c.put("username", created.user().getUsername());
            c.put("password", created.temporaryPassword());
            credentials.add(c);
        }
        audit.log("academies", academyId, "Imported " + ok.size() + " students into " + academyName);
        out.put("created", ok.size());
        out.put("credentials", credentials);
        return out;
    }

    private String uniqueUsername(String name) {
        String base = name.toLowerCase().replaceAll("[^a-z]", "");
        if (base.length() < 3) base = "student";
        base = base.substring(0, Math.min(base.length(), 14));
        for (int i = 0; i < 50; i++) {
            String candidate = base + (100 + (int) (Math.random() * 900));
            if (jdbc.queryForObject("SELECT count(*) FROM users WHERE username = ?", Integer.class, candidate) == 0) return candidate;
        }
        return base + System.nanoTime() % 100000;
    }

    private static String s(Map<String, Object> m, String k) {
        Object v = m.get(k);
        return v == null ? "" : v.toString().trim();
    }
}
