package com.nest.app.hq.service;

import com.nest.app.enrolment.dto.PersonDetails;
import com.nest.app.hq.HqAudit;
import com.nest.app.identity.entity.AcademyMembership;
import com.nest.app.identity.entity.MembershipStatus;
import com.nest.app.identity.service.IdentityRegistrationService;
import com.nest.app.identity.service.UserWithTempPassword;
import com.nest.app.validation.FieldRules;
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
import java.time.LocalDate;
import java.time.format.DateTimeFormatter;
import java.time.format.ResolverStyle;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.TreeMap;
import java.util.UUID;
import java.util.regex.Pattern;

/**
 * Adds many students to an academy from one file. The file is checked first (nothing is written) and
 * every problem is reported by row and column with what to change. Students are created only when the
 * whole file passes, in one transaction, so a file is never half imported. Each student gets a real
 * account, an academy membership and, where the file names a course and batch that exist, a place in
 * them. The temporary passwords are returned once so HQ can hand them over.
 *
 * <p>Two templates share this engine. The basic one needs a name and a mobile number; the full one
 * (template = "full") also needs the course (and the batch, where the course has batches) and checks every
 * detail it is given: date of birth, blood group, address, PIN code, guardian and so on.
 */
@Service
public class HqImport {

    static final int MAX_ROWS = 500;
    private static final Pattern MOBILE = Pattern.compile("^[6-9]\\d{9}$");
    private static final Pattern PIN_IN = Pattern.compile("^[1-9]\\d{5}$");
    private static final Pattern PLACE = Pattern.compile("^\\p{L}[\\p{L}\\p{M} .'-]*$");
    private static final Set<String> BLOOD = Set.of("A+", "A-", "B+", "B-", "AB+", "AB-", "O+", "O-");
    private static final Map<String, String> GENDERS = Map.of("male", "Male", "female", "Female", "other", "Other");
    private static final DateTimeFormatter[] DATE_FORMATS = {
            fmt("uuuu-MM-dd"), fmt("dd-MM-uuuu"), fmt("dd/MM/uuuu"), fmt("d-M-uuuu"), fmt("d/M/uuuu")};

    /** The columns of the full template, in order. */
    public static final List<String> FULL_COLUMNS = List.of("name", "mobile", "email", "gender", "date_of_birth", "blood_group", "alt_phone",
            "guardian_name", "guardian_mobile", "address_line1", "address_line2", "landmark", "city", "district", "state", "country", "pin_code",
            "course", "batch", "joining_date");

    /** Other ways a header is written, mapped to the column they mean. */
    private static final Map<String, String> ALIASES = Map.ofEntries(
            Map.entry("dob", "date_of_birth"), Map.entry("birth_date", "date_of_birth"), Map.entry("date_of_joining", "joining_date"),
            Map.entry("phone", "mobile"), Map.entry("mobile_number", "mobile"), Map.entry("phone_number", "mobile"),
            Map.entry("alternate_phone", "alt_phone"), Map.entry("alternate_mobile", "alt_phone"),
            Map.entry("guardian_phone", "guardian_mobile"), Map.entry("emergency_contact", "guardian_mobile"),
            Map.entry("address", "address_line1"), Map.entry("address1", "address_line1"), Map.entry("address2", "address_line2"),
            Map.entry("pincode", "pin_code"), Map.entry("pin", "pin_code"), Map.entry("postal_code", "pin_code"),
            Map.entry("student_name", "name"), Map.entry("full_name", "name"), Map.entry("email_id", "email"));

    private static DateTimeFormatter fmt(String p) {
        return DateTimeFormatter.ofPattern(p, Locale.ENGLISH).withResolverStyle(ResolverStyle.STRICT);
    }

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

    /** One problem in one cell: which column, what was there, what is wrong, and what to change. */
    public record Issue(String column, String value, String problem, String fix) {
        Map<String, Object> toJson() {
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("column", column);
            m.put("value", value);
            m.put("problem", problem);
            m.put("fix", fix);
            return m;
        }
    }

    /** A row that passed: every value already cleaned (mobile as 10 digits, gender as Male, dates parsed). */
    private record Student(int line, Map<String, String> v, LocalDate dob, LocalDate joined) {
    }

    /** The academy's courses and batches, for the file's course checks and the "course and batch list". */
    @Transactional(readOnly = true)
    public List<Map<String, Object>> reference(UUID academyId) {
        requireAcademy(academyId);
        Map<String, List<String>> byCourse = new TreeMap<>(String.CASE_INSENSITIVE_ORDER);
        for (var c : jdbc.queryForList("SELECT name FROM courses WHERE academy_id = ? AND status = 'ACTIVE'", academyId)) {
            byCourse.put((String) c.get("name"), new ArrayList<>());
        }
        for (var b : jdbc.queryForList("SELECT b.name, c.name AS course FROM batches b JOIN courses c ON c.id = b.course_id WHERE c.academy_id = ? AND b.status = 'ACTIVE' AND c.status = 'ACTIVE' ORDER BY b.name", academyId)) {
            byCourse.computeIfAbsent((String) b.get("course"), k -> new ArrayList<>()).add((String) b.get("name"));
        }
        List<Map<String, Object>> out = new ArrayList<>();
        byCourse.forEach((c, bs) -> {
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("course", c);
            m.put("batches", bs);
            out.add(m);
        });
        return out;
    }

    private String requireAcademy(UUID academyId) {
        var academy = jdbc.queryForList("SELECT name FROM academies WHERE id = ? AND closed_at IS NULL", academyId);
        if (academy.isEmpty()) throw new ResourceNotFoundException("Academy not found");
        return (String) academy.get(0).get("name");
    }

    /**
     * Checks the file ([commit] false) or checks it and then creates every student ([commit] true). A commit is
     * refused unless every row passes. [template] is "basic" or "full".
     */
    @Transactional
    public Map<String, Object> run(UUID academyId, List<Map<String, Object>> raw, boolean commit, String template) {
        String academyName = requireAcademy(academyId);
        if (raw == null || raw.isEmpty()) throw new BadRequestException("The file has no rows.");
        if (raw.size() > MAX_ROWS) throw new BadRequestException("Import at most " + MAX_ROWS + " rows at a time.");
        boolean full = "full".equals(template);

        // Courses and batches the academy actually has, by lower-cased name.
        Map<String, UUID> courses = new LinkedHashMap<>();
        Map<String, String> courseNames = new LinkedHashMap<>();
        Map<String, List<String>> batchNames = new LinkedHashMap<>();
        Map<String, UUID> batches = new LinkedHashMap<>();   // "course|batch" -> batch id
        Map<UUID, BigDecimal> fees = new LinkedHashMap<>();
        for (var c : jdbc.queryForList("SELECT id, name, default_fee FROM courses WHERE academy_id = ? AND status = 'ACTIVE'", academyId)) {
            String key = ((String) c.get("name")).toLowerCase();
            courses.put(key, (UUID) c.get("id"));
            courseNames.put(key, (String) c.get("name"));
            batchNames.put(key, new ArrayList<>());
            fees.put((UUID) c.get("id"), c.get("default_fee") == null ? BigDecimal.ZERO : (BigDecimal) c.get("default_fee"));
        }
        for (var b : jdbc.queryForList("SELECT b.id, b.name, c.name AS course FROM batches b JOIN courses c ON c.id = b.course_id WHERE c.academy_id = ? AND b.status = 'ACTIVE' ORDER BY b.name", academyId)) {
            String course = ((String) b.get("course")).toLowerCase();
            batches.put(course + "|" + ((String) b.get("name")).toLowerCase(), (UUID) b.get("id"));
            batchNames.computeIfAbsent(course, k -> new ArrayList<>()).add((String) b.get("name"));
        }

        Set<String> seenMobile = new HashSet<>(), seenEmail = new HashSet<>();
        List<Student> ok = new ArrayList<>();
        List<Map<String, Object>> bad = new ArrayList<>();
        int line = 1;
        for (var r : raw) {
            line++;
            Map<String, String> v = new LinkedHashMap<>();
            for (String col : FULL_COLUMNS) v.put(col, cell(r, col));
            List<Issue> issues = new ArrayList<>();
            check(v, issues, full, courses, courseNames, batchNames, batches, seenMobile, seenEmail);
            if (issues.isEmpty()) {
                ok.add(new Student(line, v, date(v.get("date_of_birth")), date(v.get("joining_date"))));
            } else {
                Map<String, Object> b = new LinkedHashMap<>();
                b.put("row", line);
                b.put("name", v.get("name"));
                b.put("issues", issues.stream().map(Issue::toJson).toList());
                b.put("why", String.join("; ", issues.stream().map(i -> i.column() + ": " + i.problem()).toList()));
                bad.add(b);
            }
        }

        Map<String, Object> out = new LinkedHashMap<>();
        out.put("total", raw.size());
        out.put("ready", ok.size());
        out.put("bad", bad);
        if (!commit) return out;
        if (!bad.isEmpty()) {
            throw new BadRequestException(bad.size() + (bad.size() == 1 ? " row has" : " rows have") + " problems, so nothing was created. Fix the file and check it again.");
        }

        UUID by = TenantContext.currentUserIdOrNull();
        List<Map<String, Object>> credentials = new ArrayList<>();
        Set<String> usernames = new HashSet<>();
        for (Student s : ok) {
            Map<String, String> v = s.v();
            String name = v.get("name");
            String username = uniqueUsername(name, s.dob(), usernames);
            UserWithTempPassword created = registration.createStudentWithPassword(username, name, v.get("mobile"), blankNull(v.get("email")),
                    s.dob(), blankNull(v.get("address_line1")), blankNull(v.get("city")), blankNull(v.get("state")), Role.STUDENT);
            String[] parts = name.trim().split("\\s+", 2);
            registration.applyPersonDetails(created.user(), new PersonDetails(
                    parts[0], parts.length > 1 ? parts[1] : null, blankNull(v.get("gender")), blankNull(v.get("blood_group")), blankNull(v.get("alt_phone")), null,
                    blankNull(v.get("address_line1")), blankNull(v.get("address_line2")), blankNull(v.get("landmark")), blankNull(v.get("city")),
                    blankNull(v.get("district")), blankNull(v.get("state")), blankNull(v.get("country")), blankNull(v.get("pin_code")),
                    blankNull(v.get("guardian_name")), blankNull(v.get("guardian_mobile")), null, null, null));
            AcademyMembership m = registration.createMembership(created.user().getId(), academyId, academyName, Role.STUDENT, MembershipStatus.ACTIVE, by);
            registration.setJoiningDate(m, s.joined());
            String course = v.get("course");
            if (!course.isEmpty()) {
                UUID courseId = courses.get(course.toLowerCase());
                registration.addCourseMap(m.getId(), Map.of(courseId, fees.get(courseId)));
                String batch = v.get("batch");
                if (!batch.isEmpty()) {
                    em.flush();   // the membership must exist before a batch row can point at it
                    jdbc.update("INSERT INTO batch_members (id, batch_id, membership_id, joined_at) VALUES (?, ?, ?, now())", UUID.randomUUID(),
                            batches.get(course.toLowerCase() + "|" + batch.toLowerCase()), m.getId());
                }
            }
            Map<String, Object> c = new LinkedHashMap<>();
            c.put("name", name);
            c.put("username", created.user().getUsername());
            c.put("password", created.temporaryPassword());
            credentials.add(c);
        }
        audit.log("academies", academyId, "Imported " + ok.size() + " students into " + academyName);
        out.put("created", ok.size());
        out.put("credentials", credentials);
        return out;
    }

    // ---- the checks, one column at a time ----

    /** Checks one row, cleaning values in [v] as it goes (so what is created is exactly what was checked). */
    void check(Map<String, String> v, List<Issue> out, boolean full, Map<String, UUID> courses, Map<String, String> courseNames,
                      Map<String, List<String>> batchNames, Map<String, UUID> batches, Set<String> seenMobile, Set<String> seenEmail) {
        // name
        String name = v.get("name").replaceAll("\\s+", " ");
        v.put("name", name);
        if (name.isEmpty()) out.add(new Issue("name", "", "is empty", "Write the student's full name."));
        else if (!FieldRules.isPersonName(name)) out.add(new Issue("name", name, "has digits or symbols, or is too short or long", "Use letters and spaces only, 2 to 60 characters. Example: Ananya Rao."));

        // mobile
        String mobile = v.get("mobile").replaceAll("[\\s-]", "");
        String stripped = mobile.replaceFirst("^(\\+91|91|0)(?=\\d{10}$)", "");
        if (MOBILE.matcher(stripped).matches()) mobile = stripped;
        v.put("mobile", mobile);
        boolean mobileOk = MOBILE.matcher(mobile).matches();
        if (mobile.isEmpty()) out.add(new Issue("mobile", "", "is empty", "Write the 10-digit mobile number."));
        else if (!mobileOk) out.add(new Issue("mobile", mobile, "is not a valid Indian mobile number", "Use exactly 10 digits starting with 6, 7, 8 or 9. Example: 9845012345."));
        else if (!seenMobile.add(mobile)) out.add(new Issue("mobile", mobile, "appears more than once in this file", "Each student needs their own number. Remove or correct the duplicate row."));
        else if (mobileTaken(mobile)) out.add(new Issue("mobile", mobile, "is already registered on Owleo", "Use a different number, or leave this student out: they already have an account."));

        // email
        String email = v.get("email");
        if (!email.isEmpty()) {
            if (!FieldRules.isEmail(email)) out.add(new Issue("email", email, "is not a valid email address", "Write it like name@example.com, or leave it empty."));
            else if (!seenEmail.add(email.toLowerCase())) out.add(new Issue("email", email, "appears more than once in this file", "Each student needs their own email, or leave it empty."));
            else if (emailTaken(email)) out.add(new Issue("email", email, "already has an Owleo account", "Use a different email, or leave it empty."));
        }

        // gender
        String gender = v.get("gender");
        if (!gender.isEmpty()) {
            String g = GENDERS.get(gender.toLowerCase());
            if (g == null) out.add(new Issue("gender", gender, "is not one of the allowed values", "Write Male, Female or Other."));
            else v.put("gender", g);
        }

        // date of birth
        LocalDate dob = null;
        String dobText = v.get("date_of_birth");
        if (!dobText.isEmpty()) {
            dob = date(dobText);
            LocalDate today = LocalDate.now();
            if (dob == null) out.add(new Issue("date_of_birth", dobText, "is not a real date", "Write it as DD-MM-YYYY, for example 14-05-2010."));
            else if (dob.isAfter(today)) out.add(new Issue("date_of_birth", dobText, "is in the future", "Check the date of birth."));
            else if (ChronoUnit.YEARS.between(dob, today) > 100 || ChronoUnit.YEARS.between(dob, today) < 2) out.add(new Issue("date_of_birth", dobText, "gives an age under 2 or over 100", "Check the year."));
        }

        // blood group
        String blood = v.get("blood_group").toUpperCase().replaceAll("\\s", "");
        if (!blood.isEmpty()) {
            if (!BLOOD.contains(blood)) out.add(new Issue("blood_group", v.get("blood_group"), "is not a blood group", "Use one of A+, A-, B+, B-, AB+, AB-, O+, O-."));
            else v.put("blood_group", blood);
        }

        // alternate phone and guardian
        String alt = v.get("alt_phone");
        if (!alt.isEmpty() && !FieldRules.isValidPhone(alt, false)) out.add(new Issue("alt_phone", alt, "is not a valid phone number", "Write a real number, with its country code if it is not Indian."));
        String gName = v.get("guardian_name").replaceAll("\\s+", " ");
        v.put("guardian_name", gName);
        if (!gName.isEmpty() && !FieldRules.isPersonName(gName)) out.add(new Issue("guardian_name", gName, "has digits or symbols, or is too short or long", "Use letters and spaces only."));
        String gMobile = v.get("guardian_mobile");
        if (!gMobile.isEmpty() && !FieldRules.isValidPhone(gMobile, false)) out.add(new Issue("guardian_mobile", gMobile, "is not a valid phone number", "Write a real number with 10 digits."));
        if (full && dob != null && ChronoUnit.YEARS.between(dob, LocalDate.now()) < 18) {
            if (gName.isEmpty()) out.add(new Issue("guardian_name", "", "is required for a student under 18", "Write the parent or guardian's name."));
            if (gMobile.isEmpty()) out.add(new Issue("guardian_mobile", "", "is required for a student under 18", "Write the parent or guardian's mobile number."));
        }

        // address
        limit(out, v, "address_line1", 160);
        limit(out, v, "address_line2", 160);
        limit(out, v, "landmark", 80);
        for (String col : List.of("city", "district", "state", "country")) {
            String val = v.get(col);
            if (!val.isEmpty() && (val.length() > 100 || !PLACE.matcher(val).matches())) out.add(new Issue(col, val, "has digits or symbols, or is too long", "Use letters and spaces only, up to 100 characters."));
        }
        String pin = v.get("pin_code").replaceAll("\\s", "");
        String country = v.get("country");
        boolean india = country.isEmpty() || country.equalsIgnoreCase("india") || country.equalsIgnoreCase("in");
        if (!pin.isEmpty()) {
            if (india ? !PIN_IN.matcher(pin).matches() : !FieldRules.isPostalCode(pin)) {
                out.add(new Issue("pin_code", pin, india ? "is not a valid Indian PIN code" : "does not look like a postal code", india ? "Use 6 digits, not starting with 0. Example: 560038." : "Use 3 to 10 letters or digits."));
            } else {
                v.put("pin_code", pin);
            }
        }

        // joining date
        String joinText = v.get("joining_date");
        if (!joinText.isEmpty()) {
            LocalDate j = date(joinText);
            if (j == null) out.add(new Issue("joining_date", joinText, "is not a real date", "Write it as DD-MM-YYYY, for example 01-06-2026."));
            else if (j.isAfter(LocalDate.now())) out.add(new Issue("joining_date", joinText, "is in the future", "Use today's date or earlier."));
            else if (j.isBefore(LocalDate.of(2000, 1, 1))) out.add(new Issue("joining_date", joinText, "is before 2000", "Check the year."));
            else if (dob != null && j.isBefore(dob)) out.add(new Issue("joining_date", joinText, "is before the date of birth", "Check both dates."));
        }

        // course and batch
        String course = v.get("course"), batch = v.get("batch");
        String ck = course.toLowerCase();
        List<String> known = new ArrayList<>(courseNames.values());
        if (course.isEmpty()) {
            if (full) out.add(new Issue("course", "", "is empty", "Write the course the student joins. This academy has: " + listOrNone(known) + "."));
            else if (!batch.isEmpty()) out.add(new Issue("batch", batch, "needs a course", "Fill the course column too, or empty the batch."));
        } else if (!courses.containsKey(ck)) {
            String near = closest(course, known);
            out.add(new Issue("course", course, "is not a course of this academy",
                    (near == null ? "" : "Did you mean " + near + "? ") + "Courses here: " + listOrNone(known) + ". Spell it exactly as shown."));
        } else {
            List<String> bs = batchNames.getOrDefault(ck, List.of());
            String shown = courseNames.get(ck);
            if (batch.isEmpty()) {
                if (full && !bs.isEmpty()) out.add(new Issue("batch", "", "is empty", shown + " has these batches: " + String.join(", ", bs) + ". Write one of them."));
            } else if (!batches.containsKey(ck + "|" + batch.toLowerCase())) {
                String near = closest(batch, bs);
                out.add(new Issue("batch", batch, "is not a batch of " + shown,
                        bs.isEmpty() ? shown + " has no batches yet. Empty this cell or create the batch first."
                                : (near == null ? "" : "Did you mean " + near + "? ") + shown + " has: " + String.join(", ", bs) + "."));
            }
        }
    }

    private static void limit(List<Issue> out, Map<String, String> v, String col, int max) {
        if (v.get(col).length() > max) out.add(new Issue(col, v.get(col), "is longer than " + max + " characters", "Shorten it."));
    }

    private static String listOrNone(List<String> l) {
        return l.isEmpty() ? "no courses yet" : String.join(", ", l);
    }

    /** The known name closest to [text] (case-insensitive, at most 2 edits away, or contained in it), or null. */
    static String closest(String text, List<String> known) {
        String t = text.toLowerCase();
        String best = null;
        int bestD = 3;
        for (String k : known) {
            String kl = k.toLowerCase();
            int d = kl.contains(t) || t.contains(kl) ? 1 : distance(t, kl);
            if (d < bestD) {
                bestD = d;
                best = k;
            }
        }
        return best;
    }

    private static int distance(String a, String b) {
        int[] prev = new int[b.length() + 1], cur = new int[b.length() + 1];
        for (int j = 0; j <= b.length(); j++) prev[j] = j;
        for (int i = 1; i <= a.length(); i++) {
            cur[0] = i;
            for (int j = 1; j <= b.length(); j++) {
                cur[j] = Math.min(Math.min(cur[j - 1] + 1, prev[j] + 1), prev[j - 1] + (a.charAt(i - 1) == b.charAt(j - 1) ? 0 : 1));
            }
            int[] t = prev;
            prev = cur;
            cur = t;
        }
        return prev[b.length()];
    }

    /** A date in DD-MM-YYYY, DD/MM/YYYY or YYYY-MM-DD form, or null if it is not a real date. */
    static LocalDate date(String text) {
        if (text == null || text.isBlank()) return null;
        for (DateTimeFormatter f : DATE_FORMATS) {
            try {
                return LocalDate.parse(text.trim(), f);
            } catch (RuntimeException ignored) {
                // try the next shape
            }
        }
        return null;
    }

    private boolean mobileTaken(String mobile) {
        Integer n = jdbc.queryForObject("SELECT count(*) FROM users WHERE phone_hash = ?", Integer.class, hasher.hash(mobile));
        return n != null && n > 0;
    }

    private boolean emailTaken(String email) {
        Integer n = jdbc.queryForObject("SELECT count(*) FROM users WHERE lower(email) = lower(?)", Integer.class, email);
        return n != null && n > 0;
    }

    /**
     * The usernames to try for a student, best first. The number on the end is never more than 3 digits.
     * With a date of birth: vishruth22 (first name and day), vishruthk22 (with the first letter of the second
     * name, when there is one), then the day with one more digit, vishruth221 to vishruth229 and vishruthk221 to
     * vishruthk229, then vishruth100 to vishruth999. Without one: vishruth, vishruthk, then vishruth1 to vishruth999.
     */
    static List<String> usernameCandidates(String name, LocalDate dob) {
        String[] words = name.trim().split("\\s+");
        String first = words[0].toLowerCase().replaceAll("[^a-z]", "");
        if (first.length() < 3) first = name.toLowerCase().replaceAll("[^a-z]", "");
        if (first.length() < 3) first = "student";
        first = first.substring(0, Math.min(first.length(), 16));
        String initial = "";
        if (words.length > 1) {
            String second = words[words.length - 1].toLowerCase().replaceAll("[^a-z]", "");
            if (!second.isEmpty()) initial = second.substring(0, 1);
        }
        String day = dob == null ? "" : String.format("%02d", dob.getDayOfMonth());
        List<String> out = new ArrayList<>();
        out.add(first + day);
        if (!initial.isEmpty()) out.add(first + initial + day);
        if (dob != null) {
            for (int n = 1; n <= 9; n++) {
                out.add(first + day + n);
                if (!initial.isEmpty()) out.add(first + initial + day + n);
            }
            for (int n = 100; n <= 999; n++) out.add(first + n);
        } else {
            for (int n = 1; n <= 999; n++) out.add((initial.isEmpty() ? first : first + initial) + n);
        }
        // The day plus a digit (vishruth221) can equal first name plus a number (vishruth221): keep each once.
        return new ArrayList<>(new java.util.LinkedHashSet<>(out));
    }

    /** The first candidate nobody has, in the database or earlier in this file. */
    private String uniqueUsername(String name, LocalDate dob, Set<String> usedInFile) {
        for (String candidate : usernameCandidates(name, dob)) {
            if (usedInFile.contains(candidate)) continue;
            Integer n = jdbc.queryForObject("SELECT count(*) FROM users WHERE lower(username) = ?", Integer.class, candidate);
            if (n != null && n == 0) {
                usedInFile.add(candidate);
                return candidate;
            }
        }
        String fallback = "student" + System.nanoTime() % 1000000;
        usedInFile.add(fallback);
        return fallback;
    }

    /** A cell by column name: the header may be written with spaces or capitals, or by one of its other names. */
    private static String cell(Map<String, Object> row, String column) {
        for (var e : row.entrySet()) {
            String key = e.getKey() == null ? "" : e.getKey().trim().toLowerCase().replaceAll("[\\s-]+", "_");
            if (ALIASES.getOrDefault(key, key).equals(column) && e.getValue() != null && !e.getValue().toString().trim().isEmpty()) {
                return e.getValue().toString().trim();
            }
        }
        return "";
    }

    private static String blankNull(String s) {
        return s == null || s.isBlank() ? null : s.trim();
    }
}
