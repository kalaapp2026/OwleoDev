package com.nest.app.hq.demo;

import com.nest.app.hq.service.HqApprovals;
import com.nest.app.hq.service.HqBilling;
import com.nest.common.crypto.PiiEncryptor;
import com.nest.common.crypto.PiiHasher;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Component;

import java.math.BigDecimal;
import java.sql.Timestamp;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.YearMonth;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Random;
import java.util.Set;
import java.util.UUID;

/**
 * Fills an EMPTY database schema with a believable platform - about 45 academies over twelve months,
 * their people, classes, attendance, fees, six months of bills and payments, offers, add-ons and
 * expenses - so the HQ console can be looked at, demonstrated and tested with real-shaped data.
 *
 * <p>It is off unless {@code nest.hq-demo.enabled=true}, and it REFUSES to run against the schema
 * named {@code nest}, which is where real data lives. Point a second backend at a throwaway schema:
 * <pre>NEST_HQ_DEMO_ENABLED=true DB_SCHEMA=nest_hqdemo SERVER_PORT=8082 mvn -pl monolith spring-boot:run</pre>
 * Everything is generated from a fixed seed, so the demo is the same every time. Every account it
 * creates has the password {@value #PASSWORD}.
 */
@Component
@ConditionalOnProperty(name = "nest.hq-demo.enabled", havingValue = "true")
public class HqDemoSeeder implements ApplicationRunner {

    private static final Logger log = LoggerFactory.getLogger(HqDemoSeeder.class);
    static final String PASSWORD = "Demo@1234";

    private static final String[] FIRST = {"Nrityanjali", "Sur Sangam", "Kala Mandir", "Swarna", "Taal", "Rhythm House", "Raaga", "Pratibha",
            "Naadam", "Chitrakala", "Abhinaya", "Madhuban", "Lahari", "Spandan", "Ghungroo", "Sargam", "Ananda", "Vaadya", "Rangmanch",
            "Tarang", "Indradhanush", "Mudra", "Sapthaswara", "Bhavana", "Shruti", "Lalitha", "Utsav", "Aarohan", "Kalpavriksha", "Veena",
            "Nupur", "Swaranjali", "Drishti", "Kalarang", "Madhurya", "Hamsadhwani", "Panchatantra", "Prerana", "Mayura", "Sadhana", "Tilak",
            "Navarasa", "Chandrika", "Gandharva", "Kinkini"};
    private static final String[][] TYPES = {
            {"Dance", "DANCE", "Dance Academy|School of Dance|Nritya Kendra"},
            {"Music", "MUSIC", "Music Academy|Conservatory|Sangeet Vidyalaya"},
            {"Fine Arts", "FINE_ARTS", "Art Studio|Fine Arts Institute|Kala Kendra"},
            {"Theatre", "THEATRE", "Theatre Company|Drama School"},
            {"Multi", "MULTI_DISCIPLINE", "Performing Arts Academy|Arts Centre"}};
    private static final String[][] CITIES = {{"Bengaluru", "Karnataka", "560"}, {"Chennai", "Tamil Nadu", "600"}, {"Hyderabad", "Telangana", "500"},
            {"Pune", "Maharashtra", "411"}, {"Mumbai", "Maharashtra", "400"}, {"Kochi", "Kerala", "682"}, {"Mysuru", "Karnataka", "570"},
            {"Coimbatore", "Tamil Nadu", "641"}, {"Ahmedabad", "Gujarat", "380"}, {"Delhi NCR", "Delhi", "110"}, {"Kolkata", "West Bengal", "700"},
            {"Jaipur", "Rajasthan", "302"}};
    private static final String[] OWNERS = {"Ritika Shah", "Meera Krishnan", "Arjun Nair", "Kavya Iyer", "Rahul Menon", "Divya Rao", "Sanjay Kulkarni",
            "Neha Gupta", "Vikram Pillai", "Anita Desai", "Karthik Subramanian", "Pooja Verma", "Suresh Babu", "Lakshmi Narayan", "Farah Khan",
            "Rohit Joshi", "Sneha Reddy", "Manoj Tiwari"};
    private static final String[] FN_F = {"Ananya", "Diya", "Kavya", "Sanya", "Myra", "Ishita", "Aadhya", "Meera", "Riya", "Navya", "Tara", "Pooja", "Neha", "Sneha", "Lakshmi", "Aditi", "Zara", "Mahika", "Pranavi", "Sara"};
    private static final String[] FN_M = {"Aarav", "Vivaan", "Arjun", "Rohan", "Ishaan", "Kabir", "Aditya", "Vihaan", "Reyansh", "Dev", "Karthik", "Rahul", "Siddharth", "Nikhil", "Yash", "Aryan", "Imran", "Varun", "Harsh", "Tejas"};
    private static final String[] LN = {"Sharma", "Patel", "Iyer", "Nair", "Reddy", "Menon", "Gupta", "Verma", "Shah", "Joshi", "Rao", "Kulkarni", "Desai", "Singh", "Khan", "Mehta", "Pillai", "Das", "Bhat", "Krishnan"};
    private static final Map<String, String[]> COURSES = Map.of(
            "Dance", new String[]{"Bharatnatyam", "Contemporary Dance", "Kathak", "Hip-hop"},
            "Music", new String[]{"Guitar Beginner", "Piano Basics", "Carnatic Vocals", "Hindustani Vocals", "Violin", "Drums"},
            "Fine Arts", new String[]{"Watercolor Painting", "Sketching", "Calligraphy"},
            "Theatre", new String[]{"Acting Basics", "Voice and Speech", "Improv"});
    private static final String[] BANKS = {"HDFC Bank", "ICICI Bank", "State Bank of India", "Axis Bank", "Kotak Mahindra Bank", "Canara Bank", "Bank of Baroda"};
    private static final String[] IFSC = {"HDFC", "ICIC", "SBIN", "UTIB", "KKBK", "CNRB", "BARB"};
    private static final String[] GATEWAYS = {"Razorpay", "Cashfree", "PayU"};
    private static final String[] MERCHANT = {"rzp_live_", "cf_prod_", "payu_"};

    private final JdbcTemplate jdbc;
    private final PiiEncryptor encryptor;
    private final PiiHasher hasher;
    private final PasswordEncoder encoder;
    private final HqBilling billing;
    private final HqApprovals approvals;
    private final String schema;
    private final Random r = new Random(20261010);
    private final Set<String> usedPhones = new HashSet<>();
    private int userSeq = 0;

    public HqDemoSeeder(JdbcTemplate jdbc, PiiEncryptor encryptor, PiiHasher hasher, PasswordEncoder encoder, HqBilling billing, HqApprovals approvals,
                        @Value("${DB_SCHEMA:nest}") String schema) {
        this.jdbc = jdbc;
        this.encryptor = encryptor;
        this.hasher = hasher;
        this.encoder = encoder;
        this.billing = billing;
        this.approvals = approvals;
        this.schema = schema;
    }

    private record Acad(UUID id, String name, String type, String category, String city, String state, String pin, String plan, String owner,
                        LocalDateTime joined, int students, int trainers, double att, double fee, double engage, String fate, UUID ownerUser,
                        List<UUID> studentMemberships, List<UUID> trainerMemberships, List<UUID> batches, Map<UUID, List<UUID>> batchMembers) {
    }

    @Override
    public void run(ApplicationArguments args) {
        if ("nest".equalsIgnoreCase(schema)) {
            log.error("HQ demo data refuses to run against the 'nest' schema, where real data lives. Set DB_SCHEMA to a throwaway schema (for example nest_hqdemo).");
            return;
        }
        Integer existing = jdbc.queryForObject("SELECT count(*) FROM academies", Integer.class);
        if (existing != null && existing > 0) {
            log.info("HQ demo data: schema '{}' already has academies, leaving it alone.", schema);
            return;
        }
        long t0 = System.currentTimeMillis();
        log.warn("HQ demo data: filling schema '{}' with sample academies. Do not use this schema for real data.", schema);

        seedPlans();
        List<Acad> academies = seedAcademies();
        seedActivity(academies);
        seedBankAccounts(academies);
        seedCatalog(academies);
        seedBilling(academies);
        applyFates(academies);
        seedExpenses();
        seedBatchStates();
        seedPipeline(academies);
        seedSupportAndExits(academies);
        seedMarketing(academies);
        seedArtistsAndEvents(academies);
        seedTransfers(academies);
        seedProviders(academies);
        seedPosts(academies);
        seedAudit();
        log.warn("HQ demo data: done in {} s. Sign in as superadmin / SuperAdmin@123.", (System.currentTimeMillis() - t0) / 1000);
    }

    // ------------------------------------------------------------------ plans

    private void seedPlans() {
        jdbc.update("UPDATE billing_plans SET active = FALSE, popular = FALSE");
        String sql = """
                INSERT INTO billing_plans (code, display_name, monthly_price, max_students, max_trainers, active, tone, popular, modules)
                VALUES (?, ?, ?, ?, ?, TRUE, ?, ?, ?)
                ON CONFLICT (code) DO UPDATE SET display_name = EXCLUDED.display_name, monthly_price = EXCLUDED.monthly_price,
                  max_students = EXCLUDED.max_students, max_trainers = EXCLUDED.max_trainers, active = TRUE, tone = EXCLUDED.tone,
                  popular = EXCLUDED.popular, modules = EXCLUDED.modules""";
        jdbc.update(sql, "STARTER", "Starter", 999, 100, 5, "blue", false, "");
        jdbc.update(sql, "GROWTH", "Growth", 2499, 400, 20, "gold", true, "events,services,study,priority");
        jdbc.update(sql, "PRO", "Pro", 4999, null, null, "violet", false, "events,services,study,branding,priority,manager");
    }

    // ------------------------------------------------------------------ academies and people

    private List<Acad> seedAcademies() {
        List<Acad> out = new ArrayList<>();
        LocalDateTime now = LocalDateTime.now();
        String hash = encoder.encode(PASSWORD);
        int total = 45;
        for (int i = 0; i < total; i++) {
            String[] type = TYPES[r.nextInt(TYPES.length)];
            String[] suffix = type[2].split("\\|");
            String name = FIRST[i % FIRST.length] + " " + suffix[r.nextInt(suffix.length)];
            String[] city = CITIES[r.nextInt(CITIES.length)];
            double p = r.nextDouble();
            String plan = p < .40 ? "STARTER" : p < .78 ? "GROWTH" : "PRO";
            // The first two are the old, big ones; the rest join across the year, with a few in the last weeks.
            int daysAgo = i == 0 ? 330 : i == 1 ? 300 : i >= total - 3 ? 5 + r.nextInt(20) : 10 + r.nextInt(320);
            LocalDateTime joined = now.minusDays(daysAgo);
            int students = switch (plan) { case "STARTER" -> 8 + r.nextInt(30); case "GROWTH" -> 25 + r.nextInt(35); default -> 40 + r.nextInt(50); };
            int trainers = switch (plan) { case "STARTER" -> 2 + r.nextInt(3); case "GROWTH" -> 3 + r.nextInt(4); default -> 5 + r.nextInt(5); };
            // A few Starter academies are right at their student limit, for the "near plan limit" alert.
            if (plan.equals("STARTER") && (i == 4 || i == 11 || i == 19)) students = 91 + r.nextInt(8);
            String fate = i >= total - 3 ? "trial" : (i == 7 || i == 14 || i == 22 || i == 30) ? "churn" : (i == 9 || i == 17 || i == 26) ? "pastdue" : (i == 12 || i == 24) ? "quiet" : "live";
            double att = .62 + r.nextDouble() * .35, fee = .66 + r.nextDouble() * .32, engage = .5 + r.nextDouble() * .42;
            if (fate.equals("churn")) { att = .35 + r.nextDouble() * .2; fee = .3 + r.nextDouble() * .2; engage = .1 + r.nextDouble() * .15; }
            if (fate.equals("pastdue")) fee = .34 + r.nextDouble() * .18;
            if (fate.equals("quiet")) engage = .25 + r.nextDouble() * .2;
            String owner = OWNERS[r.nextInt(OWNERS.length)];
            UUID id = UUID.randomUUID();
            String email = slug(name) + "@demo.owleo.test";
            String phone = phone();
            jdbc.update("""
                    INSERT INTO academies (id, name, category, address, city, state, contact_number, email, plan, status, created_at, updated_at,
                                           owner_name, owner_phone, owner_email, pin_code, go_live_on, district, country)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'ACTIVE', ?, ?, ?, ?, ?, ?, ?, ?, 'India')""",
                    id, name, type[1], (10 + r.nextInt(80)) + ", Main Road", city[0], city[1], phone, email, plan, Timestamp.valueOf(joined), Timestamp.valueOf(joined),
                    owner, phone(), slug(owner) + "@" + slug(name) + ".in", city[2] + (100 + r.nextInt(899)), joined.toLocalDate(), city[0]);

            UUID ownerUser = createUser(owner, "ACADEMY_ADMIN", joined, engage, hash, null);
            jdbc.update("INSERT INTO academy_memberships (id, user_id, academy_id, role_type, academy_name, status, created_at, joining_date) VALUES (?, ?, ?, 'ACADEMY_ADMIN', ?, 'ACTIVE', ?, ?)",
                    UUID.randomUUID(), ownerUser, id, name, Timestamp.valueOf(joined), joined.toLocalDate());
            List<UUID> studentMs = new ArrayList<>(), trainerMs = new ArrayList<>();
            for (int t = 0; t < trainers; t++) {
                trainerMs.add(member(id, name, "TRAINER", joined, now, engage, hash));
            }
            for (int s = 0; s < students; s++) {
                studentMs.add(member(id, name, "STUDENT", joined, now, engage, hash));
            }
            out.add(new Acad(id, name, type[0], type[1], city[0], city[1], city[2], plan, owner, joined, students, trainers, att, fee, engage, fate, ownerUser,
                    studentMs, trainerMs, new ArrayList<>(), new java.util.HashMap<>()));
        }
        log.info("HQ demo data: {} academies and {} users", out.size(), userSeq);
        return out;
    }

    private UUID member(UUID academyId, String academyName, String role, LocalDateTime joined, LocalDateTime now, double engage, String hash) {
        boolean female = r.nextDouble() < .55;
        String full = (female ? FN_F : FN_M)[r.nextInt(20)] + " " + LN[r.nextInt(20)];
        long span = Math.max(1, java.time.Duration.between(joined, now).toDays());
        LocalDateTime created = joined.plusDays(r.nextInt((int) span));
        UUID user = createUser(full, role, created, engage, hash, female ? "Female" : "Male");
        UUID m = UUID.randomUUID();
        jdbc.update("INSERT INTO academy_memberships (id, user_id, academy_id, role_type, academy_name, status, created_at, joining_date) VALUES (?, ?, ?, ?, ?, 'ACTIVE', ?, ?)",
                m, user, academyId, role, academyName, Timestamp.valueOf(created), created.toLocalDate());
        return m;
    }

    /** A date of birth: students are mostly children, everyone else an adult. */
    private String dob(String role) {
        int year = "STUDENT".equals(role) ? (r.nextDouble() < .6 ? 2008 + r.nextInt(11) : 1990 + r.nextInt(15)) : 1975 + r.nextInt(25);
        return year + "-" + String.format("%02d", 1 + r.nextInt(12)) + "-" + String.format("%02d", 1 + r.nextInt(27));
    }

    private UUID createUser(String fullName, String role, LocalDateTime created, double engage, String hash, String gender) {
        UUID id = UUID.randomUUID();
        String phone = phone();
        String dobText = r.nextDouble() < .04 ? null : dob(role);
        boolean minor = dobText != null && Integer.parseInt(dobText.substring(0, 4)) > LocalDate.now().getYear() - 18;
        LocalDateTime seen = r.nextDouble() < engage ? LocalDateTime.now().minusHours(r.nextInt(24 * 6)) : LocalDateTime.now().minusDays(10 + r.nextInt(50));
        jdbc.update("""
                INSERT INTO users (id, username, full_name, phone, phone_hash, email, role_type, password_hash, gender, status, created_at, updated_at, last_seen_at,
                                   address, dob, emergency_contact, guardian_name, city)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'ACTIVE', ?, ?, ?, ?, ?, ?, ?, 'Bengaluru')""",
                id, "demo" + (++userSeq), fullName, encryptor.encrypt(phone), hasher.hash(phone), r.nextDouble() < .06 ? null : slug(fullName) + userSeq + "@demo.owleo.test", role, hash, gender,
                Timestamp.valueOf(created), Timestamp.valueOf(created), Timestamp.valueOf(seen),
                r.nextDouble() < .07 ? null : encryptor.encrypt((10 + r.nextInt(90)) + ", Lake View Main Road"),
                dobText == null ? null : encryptor.encrypt(dobText),
                r.nextDouble() < .05 ? null : encryptor.encrypt(phone()),
                "STUDENT".equals(role) && minor && r.nextDouble() > .05 ? (r.nextBoolean() ? "Mr " : "Mrs ") + LN[r.nextInt(20)] : null);
        return id;
    }

    // ------------------------------------------------------------------ classes, attendance, fees

    private void seedActivity(List<Acad> academies) {
        LocalDate today = LocalDate.now();
        YearMonth last = YearMonth.now().minusMonths(1);
        for (Acad a : academies) {
            String[] names = a.type().equals("Multi") ? flatten() : COURSES.get(a.type());
            int courses = Math.min(names.length, 3 + r.nextInt(2));
            for (int c = 0; c < courses; c++) {
                UUID course = UUID.randomUUID();
                String cat = a.type().equals("Multi") ? categoryOf(names[c]) : a.category();
                BigDecimal fee = BigDecimal.valueOf(8 + r.nextInt(8)).multiply(BigDecimal.valueOf(100));
                Set<UUID> billed = new HashSet<>(); // a student in both batches of a course is billed once
                jdbc.update("INSERT INTO courses (id, academy_id, category, name, fee_cycle, default_fee, status, created_at, updated_at) VALUES (?, ?, ?, ?, 'MONTHLY', ?, 'ACTIVE', ?, ?)",
                        course, a.id(), cat, names[c], fee, Timestamp.valueOf(a.joined()), Timestamp.valueOf(a.joined()));
                for (String b : new String[]{"Batch A", "Batch B"}) {
                    UUID batch = UUID.randomUUID();
                    jdbc.update("INSERT INTO batches (id, course_id, name, batch_type, status, start_date) VALUES (?, ?, ?, 'REGULAR', 'ACTIVE', ?)", batch, course, b, a.joined().toLocalDate());
                    a.batches().add(batch);
                    UUID trainer = a.trainerMemberships().get(r.nextInt(a.trainerMemberships().size()));
                    jdbc.update("INSERT INTO batch_trainers (batch_id, trainer_membership_id) VALUES (?, ?)", batch, trainer);
                    jdbc.update("INSERT INTO trainer_course_batches (membership_id, course_id, batch_id) VALUES (?, ?, ?)", trainer, course, batch);
                    List<UUID> members = new ArrayList<>();
                    for (UUID s : a.studentMemberships()) {
                        if (r.nextDouble() < 1.0 / (courses * 2) * 1.6) {
                            members.add(s);
                            jdbc.update("INSERT INTO batch_members (id, batch_id, membership_id, joined_at) VALUES (?, ?, ?, now())", UUID.randomUUID(), batch, s);
                        }
                    }
                    a.batchMembers().put(batch, members);
                    // Six sessions in the last four weeks, attended at the academy's own rate.
                    for (int k = 0; k < 6; k++) {
                        UUID ci = UUID.randomUUID();
                        LocalDate d = today.minusDays(2 + k * 5L);
                        jdbc.update("INSERT INTO class_instances (id, batch_id, date, start_time, end_time, status) VALUES (?, ?, ?, '17:00', '18:00', 'HELD')", ci, batch, d);
                        for (UUID m : members) {
                            jdbc.update("INSERT INTO attendance (id, class_instance_id, membership_id, status, marked_by, marked_at) VALUES (?, ?, ?, ?, ?, ?)",
                                    UUID.randomUUID(), ci, m, r.nextDouble() < a.att() ? "PRESENT" : "ABSENT", a.ownerUser(), Timestamp.valueOf(d.atTime(18, 5)));
                        }
                    }
                    // One fee slip per member for last month, paid at the academy's collection rate.
                    for (UUID m : members) {
                        if (!billed.add(m)) continue;
                        jdbc.update("""
                                INSERT INTO fee_slips (id, membership_id, course_id, period, billing_period_start, billing_period_end, amount_due, generated_at, status)
                                VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'OPEN')""",
                                UUID.randomUUID(), m, course, last.toString(), last.atDay(1), last.atEndOfMonth(), fee, Timestamp.valueOf(last.plusMonths(1).atDay(1).atStartOfDay()));
                        if (r.nextDouble() < a.fee()) {
                            jdbc.update("""
                                    INSERT INTO fee_transactions (id, membership_id, course_id, period, amount_paid, mode, recorded_by, academy_id, occurred_on, created_at)
                                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
                                    UUID.randomUUID(), m, course, last.toString(), fee, r.nextBoolean() ? "UPI" : "CASH", a.ownerUser(), a.id(), today.minusDays(r.nextInt(20)), Timestamp.valueOf(LocalDateTime.now().minusDays(r.nextInt(20))));
                        }
                    }
                }
            }
        }
    }

    private static String[] flatten() {
        List<String> all = new ArrayList<>();
        COURSES.values().forEach(v -> all.addAll(List.of(v)));
        return all.toArray(new String[0]);
    }

    private static String categoryOf(String course) {
        for (var e : COURSES.entrySet()) {
            if (List.of(e.getValue()).contains(course)) {
                return switch (e.getKey()) { case "Dance" -> "DANCE"; case "Music" -> "MUSIC"; case "Fine Arts" -> "FINE_ARTS"; default -> "THEATRE"; };
            }
        }
        return "OTHERS";
    }

    // ------------------------------------------------------------------ bank accounts, offers, add-ons

    private void seedBankAccounts(List<Acad> academies) {
        for (int i = 0; i < academies.size(); i++) {
            Acad a = academies.get(i);
            int n = r.nextDouble() < .45 ? 2 : 1;
            for (int k = 0; k < n; k++) {
                int b = r.nextInt(BANKS.length);
                String number = String.valueOf(100000000000L + (long) (r.nextDouble() * 899999999999L));
                boolean mapped = r.nextDouble() > .18;
                int g = r.nextInt(3);
                jdbc.update("""
                        INSERT INTO academy_bank_accounts (academy_id, bank, account_type, holder, account_last4, account_enc, ifsc, is_primary, gateway, merchant_id)
                        VALUES (?, ?, 'Current', ?, ?, ?, ?, ?, ?, ?)""",
                        a.id(), BANKS[b], a.name(), number.substring(number.length() - 4), encryptor.encrypt(number), IFSC[b] + "0" + (100000 + r.nextInt(899999)),
                        k == 0, mapped ? GATEWAYS[g] : null, mapped ? MERCHANT[g] + (100000 + r.nextInt(899999) + k * 7) : null);
            }
        }
    }

    private void seedCatalog(List<Acad> academies) {
        LocalDate today = LocalDate.now();
        Object[][] offers = {
                {"Diwali festive offer", "DIWALI20", "PCT", 20, "all", today.minusDays(14), today.plusDays(27), 50, true},
                {"Referral credit", "REFER500", "FLAT", 500, "all", LocalDate.of(today.getYear(), 1, 1), LocalDate.of(today.getYear(), 12, 31), 100, true},
                {"Growth upgrade deal", "GROW15", "PCT", 15, "GROWTH", today.minusDays(80), today.minusDays(20), 30, true},
                {"First month free on Pro", "PROFREE", "FREE", 1, "PRO", today.plusDays(13), today.plusDays(160), 20, true},
                {"Welcome offer", "WELCOME10", "PCT", 10, "all", LocalDate.of(today.getYear(), 3, 1), LocalDate.of(today.getYear(), 12, 31), 200, false}};
        for (Object[] o : offers) {
            jdbc.update("INSERT INTO hq_offers (name, code, type, value, applies_to, starts_on, ends_on, use_limit, active) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)", o);
        }
        Object[][] addons = {
                {"WhatsApp credits pack", "5,000 messages every month", 499, "MONTH", true},
                {"Extra storage", "50 GB for photos and videos", 299, "MONTH", true},
                {"Extra trainer seats", "5 more trainer logins", 399, "MONTH", true},
                {"Custom domain", "Your own web address for the academy page", 199, "MONTH", true},
                {"Priority onboarding", "A dedicated person sets up your academy", 1500, "ONE_TIME", false}};
        List<UUID> addonIds = new ArrayList<>();
        for (Object[] a : addons) {
            UUID id = UUID.randomUUID();
            addonIds.add(id);
            jdbc.update("INSERT INTO hq_addons (id, name, description, price, billing, on_sale) VALUES (?, ?, ?, ?, ?, ?)", id, a[0], a[1], a[2], a[3], a[4]);
        }
        for (Acad a : academies) {
            if (r.nextDouble() < .35 && !a.fate().equals("trial")) {
                int k = 1 + r.nextInt(2);
                Set<Integer> picked = new HashSet<>();
                for (int i = 0; i < k; i++) picked.add(r.nextInt(4));
                for (int idx : picked) {
                    jdbc.update("INSERT INTO academy_addons (academy_id, addon_id, from_period) VALUES (?, ?, ?)", a.id(), addonIds.get(idx), YearMonth.now().minusMonths(r.nextInt(5)).toString());
                }
            }
        }
    }

    // ------------------------------------------------------------------ bills and payments

    private void seedBilling(List<Acad> academies) {
        List<String> periods = new ArrayList<>();
        for (int i = 5; i >= 0; i--) periods.add(YearMonth.now().minusMonths(i).toString());
        for (String p : periods) billing.generate(p);

        Set<UUID> pastdue = new HashSet<>();
        Set<UUID> autopay = new HashSet<>();
        for (Acad a : academies) {
            if (a.fate().equals("pastdue")) pastdue.add(a.id());
            if (r.nextDouble() < .3) autopay.add(a.id());
        }
        UUID diwali = jdbc.queryForObject("SELECT id FROM hq_offers WHERE code = 'DIWALI20'", UUID.class);
        UUID refer = jdbc.queryForObject("SELECT id FROM hq_offers WHERE code = 'REFER500'", UUID.class);

        var invoices = jdbc.queryForList("SELECT id, academy_id, period, issued_on FROM academy_invoices ORDER BY period, number");
        String[] modes = {"UPI", "Card", "Net banking", "Bank transfer"};
        for (var inv : invoices) {
            UUID id = (UUID) inv.get("id"), academy = (UUID) inv.get("academy_id");
            String period = (String) inv.get("period");
            int age = (YearMonth.now().getYear() - Integer.parseInt(period.substring(0, 4))) * 12 + YearMonth.now().getMonthValue() - Integer.parseInt(period.substring(5, 7));
            double roll = r.nextDouble();
            if (roll < .07) {
                jdbc.update("UPDATE academy_invoices SET offer_id = ? WHERE id = ?", refer, id);
                billing.recompute(id);
            } else if (age == 0 && roll < .16) {
                jdbc.update("UPDATE academy_invoices SET offer_id = ? WHERE id = ?", diwali, id);
                billing.recompute(id);
            }
            if (pastdue.contains(academy) && age <= 1) continue;
            double lim = age == 0 ? .58 : age == 1 ? .9 : .97;
            if (r.nextDouble() > lim) continue;
            BigDecimal total = jdbc.queryForObject("SELECT total FROM academy_invoices WHERE id = ?", BigDecimal.class, id);
            LocalDate issued = ((java.sql.Date) inv.get("issued_on")).toLocalDate();
            LocalDate day = issued.plusDays(r.nextInt(14));
            if (day.isAfter(LocalDate.now())) day = LocalDate.now();
            boolean partial = r.nextDouble() < .06;
            BigDecimal amount = partial ? total.multiply(BigDecimal.valueOf(.4 + r.nextDouble() * .2)).setScale(0, java.math.RoundingMode.HALF_UP) : total;
            String mode = autopay.contains(academy) ? "Autopay" : modes[r.nextInt(modes.length)];
            if (amount.signum() > 0) {
                billing.recordPayment(id, amount, mode, mode.equals("Bank transfer") ? "UTR" + (100000000000L + r.nextInt(899999999)) : "pay_" + Long.toString(r.nextLong() & 0xffffffffL, 36), day);
            }
        }
        log.info("HQ demo data: {} bills raised across {} months", invoices.size(), periods.size());
    }

    // ------------------------------------------------------------------ lifecycle

    /** Applies the ending of each academy's story: demos, closures, a quiet one. Done last so the history above is intact. */
    private void applyFates(List<Acad> academies) {
        for (Acad a : academies) {
            switch (a.fate()) {
                case "trial" -> {
                    jdbc.update("UPDATE academies SET demo_ends_on = ?, go_live_on = NULL WHERE id = ?", LocalDate.now().plusDays(4 + r.nextInt(40)), a.id());
                    jdbc.update("DELETE FROM academy_invoices WHERE academy_id = ?", a.id());
                }
                case "churn" -> {
                    LocalDateTime closed = a.joined().plusDays(60 + r.nextInt(120));
                    if (closed.isAfter(LocalDateTime.now())) closed = LocalDateTime.now().minusDays(15);
                    jdbc.update("UPDATE academies SET closed_at = ? WHERE id = ?", Timestamp.valueOf(closed), a.id());
                    jdbc.update("DELETE FROM academy_invoices WHERE academy_id = ? AND period > ?", a.id(), YearMonth.from(closed).toString());
                }
                default -> { }
            }
        }
    }

    private void seedExpenses() {
        for (int i = 0; i < 12; i++) {
            YearMonth m = YearMonth.now().minusMonths(11 - i);
            int users = jdbc.queryForObject("SELECT count(*) FROM academy_memberships WHERE created_at < ?", Integer.class, Timestamp.valueOf(m.plusMonths(1).atDay(1).atStartOfDay()));
            int acads = jdbc.queryForObject("SELECT count(*) FROM academies WHERE created_at < ?", Integer.class, Timestamp.valueOf(m.plusMonths(1).atDay(1).atStartOfDay()));
            Object[][] lines = {
                    {"SALARY", 28000 + (i >= 4 ? 2500 : 0) + (i >= 8 ? 3000 : 0)}, {"CLOUD", 2500 + Math.round(users * .5)},
                    {"MARKETING", 7000 + i * 600 + r.nextInt(1600) - 800}, {"SUPPORT", 1800 + acads * 60}, {"MESSAGING", 1200 + Math.round(users * .25)},
                    {"MISC", 2800 + r.nextInt(1200) - 600}};
            for (Object[] l : lines) {
                jdbc.update("INSERT INTO hq_expenses (month, category, amount) VALUES (?, ?, ?)", m.toString(), l[0], l[1]);
            }
        }
    }

    private void seedAudit() {
        Object[][] rows = {
                {"academies", "Edited address · demo seed"}, {"collections", "Raised bills for the last six months"},
                {"plans", "Added plan Growth at ₹2499"}, {"master", "Made Date of birth a mandatory field"}};
        for (Object[] a : rows) {
            jdbc.update("INSERT INTO hq_audit_log (actor_name, actor_role, area, detail, occurred_at) VALUES ('Platform Owner', 'SUPER', ?, ?, now() - (? * interval '1 hour'))",
                    a[0], a[1], 3 + r.nextInt(80));
        }
    }


    // ------------------------------------------------------------------ batch lifecycle

    /** Gives batches the shapes the course monitor looks for: running, upcoming, ended, outdated, no trainer, no schedule. */
    private void seedBatchStates() {
        LocalDate today = LocalDate.now();
        String[][] slots = {{"MONDAY", "WEDNESDAY", "17:00", "18:00"}, {"TUESDAY", "THURSDAY", "18:00", "19:00"}, {"SATURDAY", "SATURDAY", "10:00", "11:30"}, {"SUNDAY", "SUNDAY", "11:00", "12:30"}};
        for (var b : jdbc.queryForList("SELECT id, start_date FROM batches ORDER BY id")) {
            UUID id = (UUID) b.get("id");
            LocalDate start = ((java.sql.Date) b.get("start_date")).toLocalDate();
            double k = r.nextDouble();
            LocalDate from, end;
            String status = "ACTIVE";
            if (k < .55) { from = start; end = today.plusDays(30 + r.nextInt(120)); }
            else if (k < .70) { from = today.plusDays(5 + r.nextInt(25)); end = from.plusDays(90 + r.nextInt(120)); }
            else if (k < .88) { from = start; end = today.minusDays(5 + r.nextInt(35)); status = "INACTIVE"; }
            else { from = start; end = today.minusDays(40 + r.nextInt(80)); }   // still ACTIVE long after its end date: outdated
            if (end.isBefore(from)) end = from.plusDays(60);
            jdbc.update("UPDATE batches SET start_date = ?, end_date = ?, status = ? WHERE id = ?", from, end, status, id);
            if (r.nextDouble() < .92) {
                String[] sl = slots[r.nextInt(slots.length)];
                for (int d = 0; d < 2; d++) {
                    if (d == 1 && sl[0].equals(sl[1])) break;
                    jdbc.update("INSERT INTO schedules (id, batch_id, day_of_week, start_time, end_time, effective_from) VALUES (?, ?, ?, ?::time, ?::time, ?)",
                            UUID.randomUUID(), id, sl[d], sl[2], sl[3], from);
                }
            }
            if (!"INACTIVE".equals(status) && r.nextDouble() < .11) {
                jdbc.update("DELETE FROM batch_trainers WHERE batch_id = ?", id);
            }
        }
    }



    // ------------------------------------------------------------------ marketing, artists, events, transfers, providers, posts

    private void seedMarketing(List<Acad> academies) {
        jdbc.update("UPDATE users SET marketing_consent = (random() < 0.6) WHERE role_type = 'STUDENT'");
        List<Acad> live = academies.stream().filter(a -> "live".equals(a.fate())).toList();
        if (live.size() < 3) return;
        Object[][] rows = {
                {"Free demo class, kids", live.get(1), "META", "GUARD", "Dance", 20000, 14, "LIVE", 14200, 48200, 1620, 94},
                {"Open mic evening", live.get(0), "INAPP", "ALL", "Music", 6000, 14, "LIVE", 3800, 12400, 710, 41},
                {"Winter batch early bird", live.get(0), "BOTH", "GUARD", "Music,Dance", 15000, 30, "LIVE", 9100, 31800, 980, 63},
                {"Summer camp", live.get(1), "META", "GUARD", "Dance", 18000, 30, "ENDED", 18000, 62100, 2240, 131},
                {"Admissions drive", live.get(2), "META", "ALL", "", 12000, 7, "DRAFT", 0, 0, 0, 0}};
        for (Object[] r : rows) {
            Acad a = (Acad) r[1];
            int days = (Integer) r[6];
            boolean liveNow = "LIVE".equals(r[7]);
            jdbc.update("""
                    INSERT INTO hq_campaigns (name, academy_id, channel, audience, interests, budget, days, status, spend, reach, clicks, leads, starts_on, ends_on)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
                    r[0], a.id(), r[2], r[3], r[4], r[5], days, r[7], r[8], r[9], r[10], r[11],
                    "DRAFT".equals(r[7]) ? null : LocalDate.now().minusDays(liveNow ? days / 2 : days + 20),
                    "DRAFT".equals(r[7]) ? null : LocalDate.now().plusDays(liveNow ? days / 2 : -20));
            // What the academy pays Owleo for promotion: the ad spend so far plus a service fee, on the bill of the month it started.
            int spend = (Integer) r[8];
            if (spend > 0) {
                String period = YearMonth.from(LocalDate.now().minusDays(liveNow ? days / 2 : days + 20)).toString();
                var inv = jdbc.queryForList("SELECT id FROM academy_invoices WHERE academy_id = ? AND period = ?", a.id(), period);
                if (!inv.isEmpty()) {
                    UUID invoice = (UUID) inv.get(0).get("id");
                    jdbc.update("INSERT INTO invoice_lines (invoice_id, kind, label, amount) VALUES (?, 'MARKETING', ?, ?)", invoice, "Marketing: " + r[0], BigDecimal.valueOf(Math.round(spend * 1.15)));
                    billing.recompute(invoice);
                }
            }
        }
    }

    private UUID artistUser(String name, boolean artist) {
        return createUser(name, artist ? "ARTIST" : "GUEST", LocalDateTime.now().minusDays(30), .6, encoder.encode(PASSWORD), r.nextBoolean() ? "Female" : "Male");
    }

    private void application(UUID user, String status, String form, String city, String bio, String profiles, String checklist, boolean guardian, boolean post, boolean events,
                             int strikes, int daysAgo, String... log) {
        UUID id = UUID.randomUUID();
        jdbc.update("""
                INSERT INTO artist_applications (id, user_id, status, created_at, art_form, city, bio, profiles, checklist, guardian_ok, can_post, can_events, strikes, decided_at)
                VALUES (?, ?, ?, now() - (? * interval '1 day'), ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
                id, user, status, daysAgo, form, city, bio, profiles, checklist, guardian, post, events, strikes,
                "PENDING".equals(status) || "INFO".equals(status) ? null : Timestamp.valueOf(LocalDateTime.now().minusDays(Math.max(0, daysAgo - 1))));
        jdbc.update("INSERT INTO hq_artist_log (application_id, actor_name, text, at) VALUES (?, ?, 'Requested artist verification', now() - (? * interval '1 day'))", id, "Applicant", daysAgo);
        int i = 0;
        for (String l : log) jdbc.update("INSERT INTO hq_artist_log (application_id, actor_name, text, at) VALUES (?, 'Raghav Nair', ?, now() - (? * interval '1 hour'))", id, l, Math.max(1, (daysAgo - 1) * 24 - (i++) * 6));
    }

    private static String prof(String pl, String h, String f, String st, String m) {
        return "{\"pl\":\"" + pl + "\",\"h\":\"" + h + "\",\"f\":\"" + f + "\",\"s\":\"" + st + "\",\"m\":\"" + m + "\"}";
    }

    private void seedArtistsAndEvents(List<Acad> academies) {
        String all = "{\"name\":true,\"own\":true,\"act\":true,\"art\":true,\"pol\":true}";
        application(artistUser("Ananya Rao", false), "PENDING", "Bharatnatyam dancer", "Bengaluru", "Solo performer and teacher, 15 years of training.",
                "[" + prof("instagram", "@ananya.dances", "48.2K", "pending", "Not yet") + "," + prof("youtube", "Ananya Rao Dance", "12.6K", "pending", "Not yet") + "]", "{}", false, false, false, 0, 0);
        application(artistUser("Rohan Verma", false), "PENDING", "Indie guitarist", "Delhi", "Original songs and live sessions.",
                "[" + prof("instagram", "@rohan.strings", "21.4K", "ok", "Code in bio") + "," + prof("youtube", "Rohan Verma Music", "8.9K", "pending", "Not yet") + "]", "{}", false, false, false, 0, 1);
        application(artistUser("Kabir Sethi", false), "INFO", "Stand-up and improv", "Mumbai", "Comedy sets and improv workshops.",
                "[" + prof("youtube", "Kabir Sethi Live", "64K", "pending", "Not yet") + "]", "{}", false, false, false, 0, 3, "Asked: the Instagram bio does not show our code.");
        application(artistUser("Priya Nambiar", true), "APPROVED", "Painter", "Kochi", "Watercolour artist.",
                "[" + prof("instagram", "@priya.paints", "77K", "ok", "Code in bio") + "]", all, false, true, true, 0, 6, "Approved. Can post in Social and host events.");
        application(artistUser("Devansh Kulkarni", true), "APPROVED", "Theatre actor", "Pune", "Stage and screen.",
                "[" + prof("instagram", "@dev.on.stage", "14K", "ok", "Code in bio") + "]", all, false, true, true, 0, 9, "Approved. Can post in Social and host events.");
        UUID sus = artistUser("Lakshmi Iyer", false);
        application(sus, "SUSPENDED", "Veena player", "Bengaluru", "Classical veena.", "[" + prof("youtube", "Lakshmi Veena", "11K", "ok", "Link back") + "]", all, false, false, false, 1, 12,
                "Approved.", "Report upheld: Impersonation. Suspended. Chance 1 of 3 used.");
        application(artistUser("Vikram Das", false), "REJECTED", "Photographer", "Kolkata", "Event photographer.", "[" + prof("instagram", "@vikram.frames", "900", "bad", "Not yet") + "]", "{}", false, false, false, 0, 7,
                "Rejected: account looks new and posts match another artist.");
        jdbc.update("UPDATE artist_applications SET prev_post = TRUE, prev_events = TRUE WHERE status = 'SUSPENDED'");
        UUID prApp = jdbc.queryForObject("SELECT id FROM artist_applications WHERE status = 'APPROVED' ORDER BY created_at LIMIT 1", UUID.class);
        jdbc.update("INSERT INTO hq_artist_reports (application_id, reported_by, reporter_role, category, details) VALUES (?, 'Neha Kapoor', 'User', 'Copied or stolen work', 'The Monsoon Series looks copied from another painter''s page.')", prApp);

        // Events across academies, including an HQ pause and a cancellation.
        List<Acad> live = academies.stream().filter(a -> "live".equals(a.fate())).toList();
        if (live.size() < 9) return;
        Object[][] ev = {
                {"Bharatanatyam Arangetram Showcase", 0, -3, 18, "Indiranagar, Bengaluru", "PUBLISHED"},
                {"Kathak Footwork Masterclass", 2, 1, 17, "Kothrud, Pune", "PUBLISHED"},
                {"Open Mic Night", 1, 1, 20, "Hauz Khas, Delhi", "PUBLISHED"},
                {"Inter-academy Dance Competition", 3, 4, 10, "Palace Grounds, Bengaluru", "PUBLISHED"},
                {"Improv for Beginners", 4, 4, 18, "Bandra, Mumbai", "PUBLISHED"},
                {"Carnatic Vocal Concert", 5, 7, 18, "T Nagar, Chennai", "PUBLISHED"},
                {"Annual Day Celebration", 6, 15, 16, "School auditorium, Hyderabad", "PUBLISHED"},
                {"Rhythm Circle", 7, -6, 17, "Whitefield, Bengaluru", "PUBLISHED"},
                {"Folk Dance Fest", 8, -9, 11, "Kolkata", "PUBLISHED"},
                {"Veena Evening", 5, 8, 18, "Jayanagar, Bengaluru", "DRAFT"},
                {"Kids Theatre Camp", 8, -1, 10, "Ahmedabad", "CANCELLED"},
                {"Monsoon Art Walk", 2, 6, 9, "Fort Kochi", "PUBLISHED"}};
        for (Object[] e : ev) {
            Acad a = live.get((Integer) e[1]);
            UUID id = UUID.randomUUID();
            LocalDateTime when = LocalDate.now().plusDays((Integer) e[2]).atTime((Integer) e[3], 0);
            jdbc.update("""
                    INSERT INTO events (id, academy_id, type, title, description, event_date, end_date, location, visibility, status, audience_type, created_by)
                    VALUES (?, ?, 'PROGRAMME', ?, 'An evening of performances and workshops open to students and families.', ?, ?, ?, 'PUBLIC', ?, 'EVERYONE', ?)""",
                    id, a.id(), e[0], Timestamp.valueOf(when), Timestamp.valueOf(when.plusHours(2)), e[4], e[5], a.ownerUser());
            if ("DRAFT".equals(e[5])) jdbc.update("INSERT INTO hq_event_log (event_id, kind, actor_name, text) VALUES (?, 'HOLD', 'Farah Sheikh', 'Paused: venue under review')", id);
            if ("CANCELLED".equals(e[5])) jdbc.update("INSERT INTO hq_event_log (event_id, kind, actor_name, text) VALUES (?, 'CANCEL', 'Meena Kapoor', 'Cancelled: venue unavailable')", id);
            // A few interested people each.
            jdbc.update("""
                    INSERT INTO interests (id, user_id, event_id, created_at)
                    SELECT gen_random_uuid(), m.user_id, ?, now() FROM academy_memberships m WHERE m.academy_id = ? AND m.status = 'ACTIVE' ORDER BY random() LIMIT ?""", id, a.id(), 5 + r.nextInt(30));
        }
    }

    private void seedTransfers(List<Acad> academies) {
        List<Acad> live = academies.stream().filter(a -> "live".equals(a.fate())).toList();
        if (live.size() < 12) return;
        Acad a = live.get(10), b = live.get(11);
        jdbc.update("""
                INSERT INTO hq_transfers (academy_id, new_name, new_email, new_phone, reason, step, previous_owner)
                VALUES (?, 'Sunita Das', 'sunita.das@gmail.com', '9812345678', 'Stepping down', 'REVIEW', NULL)""", a.id());
        UUID done = UUID.randomUUID();
        jdbc.update("""
                INSERT INTO hq_transfers (id, academy_id, new_name, new_email, new_phone, reason, step, verified_from, verified_to, previous_owner, done_at)
                VALUES (?, ?, 'Vikram Rao', 'vikram.rao@outlook.com', '9822233344', 'Selling the academy', 'DONE', TRUE, TRUE, ?, now() - interval '17 days')""", done, b.id(), b.owner());
        jdbc.update("INSERT INTO hq_transfer_history (transfer_id, actor_name, text) VALUES (?, 'System', 'Both parties confirmed. Ownership moved')", done);
    }

    private void provider(String name, String person, String city, String types, String status, int price, String unit, String services, String bio, String links, String kyc, int years, int applied) {
        jdbc.update("""
                INSERT INTO hq_providers (name, person, phone, email, city, types, status, price, unit, services, bio, exp_years, links, kyc, applied_on)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
                name, person, phone(), slug(person) + "@gmail.com", city, types, status, price, unit, services, bio, years, links, kyc, LocalDate.now().minusDays(applied));
    }

    private void seedProviders(List<Acad> academies) {
        String ok = "{\"id\":true,\"biz\":true,\"call\":true,\"refs\":true}";
        String links2 = "[{\"u\":\"https://instagram.com/lensbyarjun\",\"ok\":true},{\"u\":\"https://youtube.com/@lensbyarjun\",\"ok\":true}]";
        String linksNew = "[{\"u\":\"https://instagram.com/tablatales\",\"ok\":null}]";
        provider("Lens by Arjun", "Arjun Rao", "Bengaluru", "photo", "LIVE", 6500, "per hour", "Event photography\nPortrait sessions", "Stage and event photographer for dance schools.", links2, ok, 9, 120);
        provider("Frame and Flow Studios", "Nisha Kulkarni", "Pune", "photo,video", "LIVE", 18000, "per event", "Event photo and video\nHighlight reels", "Two-person team covering recitals.", links2, ok, 7, 95);
        provider("Royal Stage Works", "Imran Sheikh", "Hyderabad", "stage,sound", "LIVE", 35000, "per event", "Stage and truss\nSound system", "Complete stage, light and sound packages.", links2, ok, 14, 150);
        provider("Petal and Pillar Decor", "Divya Menon", "Mumbai", "decor,props", "LIVE", 22000, "per event", "Entrance and stage decor", "Theme based decor for annual days.", links2, ok, 6, 80);
        provider("Gharana Costumes", "Lakshmi Pillai", "Chennai", "cost,jewel", "LIVE", 350, "per costume per day", "Bharatanatyam costumes\nTemple jewellery", "Classical costumes on rent.", links2, ok, 18, 200);
        provider("Glam by Meera", "Meera Pillai", "Bengaluru", "makeup", "LIVE", 4500, "per artist", "Stage makeup\nHair styling", "Stage makeup for dance and drama.", links2, ok, 8, 70);
        provider("Swar Sangeet Band", "Rohan Das", "Delhi NCR", "music", "SUSPENDED", 25000, "per show", "Live band", "Five piece band.", links2, ok, 5, 180);
        provider("SetCraft Designs", "Anil Nair", "Kochi", "set,props", "VERIFY", 40000, "per event", "Stage sets\nBackdrops", "Set designers for theatre.", links2, "{\"id\":true,\"call\":false}", 11, 6);
        provider("Tabla Tales Instruments", "Suresh Patil", "Pune", "instr", "REVIEW", 1500, "per instrument per day", "Tabla and harmonium", "Instrument rental with delivery.", linksNew, "{}", 10, 3);
        provider("Temple Trail Jewels", "Kavya Reddy", "Jaipur", "jewel", "APPLIED", 200, "per set per day", "Bridal and stage jewellery", "Stage jewellery for folk dance.", linksNew, "{}", 4, 1);
        provider("Mic Drop Emcees", "Farah Khan", "Mumbai", "emcee", "APPLIED", 8000, "per event", "Event anchoring", "Anchor and emcee for events.", linksNew, "{}", 3, 2);
        provider("Quick Props Hub", "Dev Malhotra", "Delhi NCR", "props", "REJECTED", 5000, "per event", "Props on rent", "Props rental.", "[{\"u\":\"https://instagram.com/quickpropshub\",\"ok\":false}]", "{}", 2, 40);

        List<Acad> live = academies.stream().filter(a -> "live".equals(a.fate())).toList();
        var provs = jdbc.queryForList("SELECT id, status FROM hq_providers WHERE status IN ('LIVE', 'SUSPENDED') ORDER BY seq");
        String[] events = {"Annual Day", "Dance recital", "Student showcase", "Workshop", "Cultural fest", "Prize distribution"};
        for (int p = 0; p < provs.size(); p++) {
            UUID pid = (UUID) provs.get(p).get("id");
            double quality = switch (p) { case 0 -> .95; case 1 -> .88; case 2 -> .8; case 3 -> .9; case 4 -> .85; case 5 -> .92; default -> .45; };
            int n = 12 + r.nextInt(20);
            for (int k = 0; k < n; k++) {
                int back = r.nextInt(170) - 14;
                boolean upcoming = back < 0;
                double roll = r.nextDouble();
                String st = upcoming ? "UPCOMING" : roll < (1 - quality) * .28 ? "CANCELLED" : "DONE";
                Integer rating = "DONE".equals(st) ? Math.max(1, Math.min(5, (int) Math.round(1 + quality * 3.9 + (r.nextDouble() - .4) * 1.6))) : null;
                jdbc.update("""
                        INSERT INTO hq_provider_jobs (provider_id, academy_id, event_name, job_date, amount, status, rating, late, issue) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)""",
                        pid, live.get(r.nextInt(live.size())).id(), events[r.nextInt(events.length)], LocalDate.now().minusDays(back), 4000 + r.nextInt(30000), st, rating,
                        "DONE".equals(st) && r.nextDouble() < (1 - quality) * .55, "DONE".equals(st) && r.nextDouble() < (1 - quality) * .18);
            }
            jdbc.update("INSERT INTO hq_provider_log (provider_id, actor_name, text) VALUES (?, 'Operations admin', 'Approved. Live now')", pid);
        }
        if (live.size() < 8) return;
        Object[][] rq = {
                {live.get(1), "photo", "Annual Day", 21, 30000, "OPEN"}, {live.get(4), "stage", "Cultural fest", 30, 60000, "OPEN"},
                {live.get(2), "decor", "Dance recital", 14, 25000, "MATCHED"}, {live.get(7), "makeup", "Student showcase", 10, 9000, "OPEN"}};
        for (Object[] q : rq) {
            UUID id = UUID.randomUUID();
            jdbc.update("INSERT INTO hq_provider_requests (id, academy_id, type_code, event_name, event_date, budget, status) VALUES (?, ?, ?, ?, ?, ?, ?)",
                    id, ((Acad) q[0]).id(), q[1], q[2], LocalDate.now().plusDays((Integer) q[3]), q[4], q[5]);
            if ("MATCHED".equals(q[5])) {
                jdbc.update("INSERT INTO hq_provider_request_sent (request_id, provider_id) SELECT ?, id FROM hq_providers WHERE types LIKE '%decor%' AND status = 'LIVE'", id);
            }
        }
    }

    private void seedPosts(List<Acad> academies) {
        // The super admin is created by the app's own bootstrap, which may run after this seeder: no HQ posts then.
        UUID hq = jdbc.queryForList("SELECT id FROM users WHERE role_type = 'SUPER_ADMIN' ORDER BY created_at LIMIT 1", UUID.class).stream().findFirst().orElse(null);
        String[] hqPosts = {"Festival season is here. Plan your annual day dates now and invite families early.", "Tip for academy owners: send fee reminders on the 1st, not the 5th."};
        for (int i = 0; hq != null && i < hqPosts.length; i++) {
            jdbc.update("INSERT INTO posts (id, author_user_id, type, content, visibility, created_at) VALUES (gen_random_uuid(), ?, 'NORMAL', ?, 'PUBLIC', now() - (? * interval '1 day'))", hq, hqPosts[i], 2 + i * 6);
        }
        String[] academyPosts = {"Rehearsals are in full swing for our winter showcase.", "New batches open next week. Call us to reserve a seat.", "Congratulations to our young dancers on the state-level win!", "A big thank you to everyone who joined our open mic evening."};
        int i = 0;
        for (Acad a : academies) {
            if (!"live".equals(a.fate()) || i >= academyPosts.length * 2) continue;
            UUID mem = a.trainerMemberships().isEmpty() ? null : jdbc.queryForList("SELECT id FROM academy_memberships WHERE academy_id = ? AND role_type = 'ACADEMY_ADMIN' LIMIT 1", UUID.class, a.id()).stream().findFirst().orElse(null);
            if (mem == null) continue;
            jdbc.update("INSERT INTO posts (id, author_membership_id, type, content, visibility, created_at) VALUES (gen_random_uuid(), ?, 'NORMAL', ?, 'PUBLIC', now() - (? * interval '1 hour'))", mem, academyPosts[i % academyPosts.length], 3 + i * 9);
            i++;
        }
    }

    // ------------------------------------------------------------------ support and exits

    private void ticket(Acad a, String kind, String cat, String pr, String status, int age, String by, String role, String subject, String body, Integer rating, Integer amount, String... replies) {
        UUID id = UUID.randomUUID();
        jdbc.update("""
                INSERT INTO hq_tickets (id, kind, academy_id, category, priority, status, raised_by, raised_role, subject, body, rating, amount, assignee, created_at, resolved_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, now() - (? * interval '1 day'), ?)""",
                id, kind, a.id(), cat, pr, status, by, role, subject, body, rating, amount, "OPEN".equals(status) ? null : "Support team", age,
                "RESOLVED".equals(status) || "CLOSED".equals(status) ? Timestamp.valueOf(LocalDateTime.now().minusDays(Math.max(0, age - 1))) : null);
        jdbc.update("INSERT INTO hq_ticket_messages (ticket_id, author, from_hq, body, at) VALUES (?, ?, FALSE, ?, now() - (? * interval '1 day'))", id, by, body, age);
        for (String reply : replies) {
            jdbc.update("INSERT INTO hq_ticket_messages (ticket_id, author, from_hq, body, at) VALUES (?, 'Support team', TRUE, ?, now() - (? * interval '1 hour'))", id, reply, Math.max(1, age * 12));
        }
    }

    private void seedSupportAndExits(List<Acad> academies) {
        List<Acad> live = academies.stream().filter(a -> "live".equals(a.fate())).toList();
        if (live.size() < 8) return;
        Acad a0 = live.get(0), a1 = live.get(1), a2 = live.get(2), a3 = live.get(3), a4 = live.get(4), a5 = live.get(5);
        ticket(a4, "ISSUE", "Login and access", "URGENT", "OPEN", 0, "Meena Kapoor", "Academy admin", "Trainers cannot log in since morning", "All 14 trainers see session expired right after entering the OTP. Classes start at 4 pm.", null, null);
        ticket(a1, "ISSUE", "Payments and payouts", "HIGH", "PROGRESS", 1, a1.owner(), "Academy owner", "Payout for 3 October has not arrived", "Fees collected last week show as settled in the app but the transfer to our second account is missing.", null, null,
                "Checking with the gateway. It was split across two accounts, so it may be pending on the second one.");
        ticket(a0, "ISSUE", "Data and sync", "MEDIUM", "WAITING", 3, a0.owner(), "Academy owner", "Offline attendance did not sync", "Attendance marked on Saturday without network is still missing for Batch B.", null, null,
                "Please ask the trainer to open the app on Wi-Fi once. Tell us if it is still missing.");
        ticket(a5, "ISSUE", "App bug", "LOW", "OPEN", 4, "Raghav Nair", "Academy admin", "Batch roster shows duplicate students", "Two students appear twice in Hip-hop Batch A.", null, null);
        ticket(a2, "ISSUE", "Billing", "MEDIUM", "RESOLVED", 6, a2.owner(), "Academy owner", "GST invoice shows the wrong address", "Please correct the registered address on invoices.", null, null, "Updated and re-issued the invoice for September.");
        ticket(a3, "ENQUIRY", "Plan and pricing", "MEDIUM", "OPEN", 1, a3.owner(), "Academy owner", "Can we move to Pro in the middle of a cycle?", "We have grown past 400 students. How is the first month billed if we upgrade on the 15th?", null, null);
        ticket(a4, "ENQUIRY", "Feature request", "LOW", "OPEN", 2, "Farah Sheikh", "Academy admin", "Parent reminders on WhatsApp", "Is there a plan to send fee and class reminders to parents on WhatsApp?", null, null);
        ticket(a0, "ENQUIRY", "Onboarding", "MEDIUM", "PROGRESS", 2, a0.owner(), "Academy owner", "Adding a second branch", "We are opening a branch in Whitefield. Can it share trainers with the Indiranagar branch?", null, null, "Yes. We will map the branch and share the steps.");
        ticket(a1, "FEEDBACK", "Product", "LOW", "CLOSED", 3, a1.owner(), "Academy owner", "The attendance flow is great", "Marking attendance takes half the time it used to.", 5, null);
        ticket(a4, "FEEDBACK", "Reports", "LOW", "OPEN", 2, "Lata Menon", "Academy admin", "Fee reports are slow to load", "The fee summary takes close to 20 seconds on a phone.", 3, null);
        ticket(a0, "FEEDBACK", "Product", "LOW", "OPEN", 1, a0.owner(), "Academy owner", "Would like bulk batch editing", "Moving 20 students between batches one by one is slow.", 4, null);
        ticket(a0, "FEE", "Charged twice", "HIGH", "OPEN", 0, "Ananya Sharma", "Student", "Charged twice for the October fee", "I paid 1200 on 5 October and was charged again on 6 October.", null, 1200);
        ticket(a1, "FEE", "Paid but shows unpaid", "HIGH", "PROGRESS", 1, "Diya Patel", "Parent", "Paid by UPI but the app shows unpaid", "UPI reference ending 4821 was debited on 4 October. The app still shows the fee as due.", null, 1500,
                "We found the payment at the gateway. Matching it to the fee now.");
        ticket(a0, "FEE", "Refund request", "MEDIUM", "OPEN", 2, "Kavya Iyer", "Parent", "Refund for a cancelled course", "We cancelled Guitar Beginner before the first class. Please refund the advance of 2400.", null, 2400);
        ticket(a1, "FEE", "Receipt or invoice", "LOW", "RESOLVED", 5, "Rohan Gupta", "Student", "Need a fee receipt for tax", "Please send the receipts for April to September.", null, null, "Sent to your registered email.");

        // Exits: one waiting on approval, one in clearance, one ready, one done.
        var people = jdbc.queryForList("""
                SELECT DISTINCT ON (m.user_id) m.user_id, m.role_type FROM academy_memberships m
                WHERE m.status = 'ACTIVE' AND m.role_type IN ('TRAINER', 'STUDENT') ORDER BY m.user_id LIMIT 40""");
        if (people.size() < 12) return;
        UUID u1 = (UUID) people.get(2).get("user_id"), u2 = (UUID) people.get(5).get("user_id"), u3 = (UUID) people.get(9).get("user_id"), u4 = (UUID) people.get(11).get("user_id");
        UUID x1 = UUID.randomUUID(), x2 = UUID.randomUUID(), x3 = UUID.randomUUID();
        jdbc.update("INSERT INTO hq_exits (id, user_id, reason, effective_on, stage) VALUES (?, ?, 'Relocating to another city', current_date + 10, 'APPROVAL')", x1, u1);
        UUID req = approvals.create("EXIT", null, "Owleo HQ", "Exit: relocating to another city", List.of(List.of("Reason", "Relocating to another city")), java.util.Map.of(), 1, "exit", x1.toString());
        jdbc.update("UPDATE hq_exits SET approval_id = ? WHERE id = ?", req, x1);
        jdbc.update("INSERT INTO hq_exits (id, user_id, reason, effective_on, stage, c_dues) VALUES (?, ?, 'Course completed', current_date - 3, 'CLEARANCE', TRUE)", x2, u2);
        jdbc.update("INSERT INTO hq_exits (id, user_id, reason, effective_on, stage, c_dues, c_handover, c_assets) VALUES (?, ?, 'Fees and schedule conflict', current_date - 1, 'CLEARANCE', TRUE, TRUE, TRUE)", x3, u3);
        jdbc.update("INSERT INTO hq_exits (id, user_id, reason, effective_on, stage, c_dues, c_handover, c_assets, done_at) VALUES (?, ?, 'Left the academy', current_date - 20, 'DONE', TRUE, TRUE, TRUE, now() - interval '20 days')", UUID.randomUUID(), u4);
        jdbc.update("UPDATE users SET status = 'INACTIVE' WHERE id = ?", u4);
        jdbc.update("UPDATE academy_memberships SET status = 'REVOKED' WHERE user_id = ?", u4);
    }

    // ------------------------------------------------------------------ onboarding and approvals

    /** Leads waiting for a demo, a demo record for every academy still on trial, and a few open requests. */
    private void seedPipeline(List<Acad> academies) {
        String[][] leads = {
                {"Nartana Kendra", "Dance", "Anjali Rao", "Mysuru", "Karnataka", "570001", "GROWTH", "180", "45"},
                {"Sapta Swara Music School", "Music", "Dinesh Pai", "Kochi", "Kerala", "682001", "STARTER", "70", "90"},
                {"Rang Tarang Arts", "Fine Arts", "Farida Sheikh", "Pune", "Maharashtra", "411001", "PRO", "420", "60"}};
        for (String[] l : leads) {
            String slug = slug(l[0]);
            jdbc.update("""
                    INSERT INTO hq_leads (name, type, academy_email, academy_phone, address_line1, city, state, pin, owner_name, owner_phone, owner_email,
                                          plan_code, est_students, demo_days, banks)
                    VALUES (?, ?, ?, ?, '12 MG Road', ?, ?, ?, ?, ?, ?, ?, ?, ?, '[]')""",
                    l[0], l[1], "hello@" + slug + ".in", phone(), l[3], l[4], l[5], l[2], phone(), slug(l[2]) + "@gmail.com", l[6], Integer.parseInt(l[7]), Integer.parseInt(l[8]));
        }
        int n = 0;
        for (Acad a : academies) {
            if (!"trial".equals(a.fate())) continue;
            LocalDate ends = jdbc.queryForObject("SELECT demo_ends_on FROM academies WHERE id = ?", LocalDate.class, a.id());
            int days = new int[]{60, 90, 45, 30}[n % 4];
            boolean done = ends != null && ends.isBefore(LocalDate.now().plusDays(10));
            jdbc.update("""
                    INSERT INTO hq_leads (stage, name, type, academy_email, academy_phone, address_line1, city, state, pin, owner_name, owner_phone, owner_email,
                                          plan_code, est_students, demo_days, banks, academy_id, demo_started_on, demo_done)
                    VALUES ('DEMO', ?, ?, ?, ?, '1 Main Road', ?, ?, ?, ?, ?, ?, ?, ?, ?, '[]', ?, ?, ?)""",
                    a.name(), a.type(), "info@" + slug(a.name()) + ".in", phone(), a.city(), a.state(), a.pin() + "001", a.owner(), phone(), slug(a.owner()) + "@gmail.com",
                    a.plan(), Math.max(40, a.students()), days, a.id(), ends == null ? LocalDate.now() : ends.minusDays(days), done);
            n++;
        }
        int live = 0;
        for (Acad a : academies) {
            if (!"live".equals(a.fate()) || live >= 3 || a.joined().isBefore(LocalDateTime.now().minusDays(60))) continue;
            jdbc.update("""
                    INSERT INTO hq_leads (stage, name, type, academy_email, academy_phone, address_line1, city, state, pin, owner_name, owner_phone, owner_email,
                                          plan_code, est_students, demo_days, banks, academy_id, demo_done, v_details, v_gateway, approved, live_since)
                    VALUES ('LIVE', ?, ?, ?, ?, '1 Main Road', ?, ?, ?, ?, ?, ?, ?, ?, 60, '[]', ?, TRUE, TRUE, TRUE, TRUE, ?)""",
                    a.name(), a.type(), "live@" + slug(a.name()) + ".in", phone(), a.city(), a.state(), a.pin() + "001", a.owner(), phone(), slug(a.owner()) + "@gmail.com",
                    a.plan(), Math.max(40, a.students()), a.id(), a.joined().toLocalDate());
            live++;
        }
        // Open requests HQ itself is holding.
        Acad x = academies.stream().filter(a -> "live".equals(a.fate()) && !"PRO".equals(a.plan())).findFirst().orElse(null);
        Acad y = academies.stream().filter(a -> "live".equals(a.fate())).skip(5).findFirst().orElse(null);
        if (x != null) {
            approvals.create("PLAN_CHANGE", x.id(), x.owner(), "Move " + x.name() + " to Pro", List.of(List.of("From", x.plan()), List.of("To", "PRO")),
                    java.util.Map.of("plan", "PRO"), 0, null, null);
        }
        if (y != null) {
            approvals.create("ACADEMY_CLOSURE", y.id(), y.owner(), "Close " + y.name(), List.of(List.of("Reason", "Relocating out of the city")),
                    java.util.Map.of(), 0, null, null);
        }
    }

    // ------------------------------------------------------------------ small helpers

    private String phone() {
        String p;
        do {
            p = (6 + r.nextInt(4)) + String.format("%09d", r.nextInt(1_000_000_000));
        } while (!usedPhones.add(p));
        return p;
    }

    private static String slug(String s) {
        return s.toLowerCase().replaceAll("[^a-z0-9]+", "");
    }

}
