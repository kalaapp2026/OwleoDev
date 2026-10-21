package com.nest.app.hq.service;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.nest.app.academy.dto.OnboardAcademyRequest;
import com.nest.app.academy.dto.OnboardAcademyResponse;
import com.nest.app.academy.entity.AcademyCategory;
import com.nest.app.academy.service.AcademyService;
import com.nest.app.hq.HqAudit;
import com.nest.common.crypto.PiiEncryptor;
import com.nest.common.exception.BadRequestException;
import com.nest.common.exception.ConflictException;
import com.nest.common.exception.ResourceNotFoundException;
import jakarta.persistence.EntityManager;
import org.springframework.context.event.EventListener;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.YearMonth;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.regex.Pattern;

/**
 * Takes a prospect from a first conversation to a live academy: register the lead, start its demo
 * (which creates the real academy and the owner's login), run the activation checks, and go live.
 *
 * <p>Going live needs all three checks: the details validated, the payment gateway mapped on the
 * primary bank account, and an HQ approval. The checks are real, not clicks: the gateway check
 * looks for an actual mapping, and the approval is a request in Approvals that someone has to decide.
 */
@Service
public class HqOnboarding {

    private static final Pattern EMAIL = Pattern.compile("^\\S+@\\S+\\.\\S+$");
    private static final Pattern MOBILE = Pattern.compile("^[6-9]\\d{9}$");
    private static final Pattern IFSC = Pattern.compile("^[A-Za-z]{4}0[A-Za-z0-9]{6}$");
    private static final Pattern ACCOUNT = Pattern.compile("^\\d{9,18}$");

    private final JdbcTemplate jdbc;
    private final HqAudit audit;
    private final ObjectMapper json;
    private final PiiEncryptor encryptor;
    private final AcademyService academyService;
    private final HqApprovals approvals;
    private final HqBilling billing;
    private final EntityManager em;

    public HqOnboarding(JdbcTemplate jdbc, HqAudit audit, ObjectMapper json, PiiEncryptor encryptor, AcademyService academyService,
                        HqApprovals approvals, HqBilling billing, EntityManager em) {
        this.jdbc = jdbc;
        this.audit = audit;
        this.json = json;
        this.encryptor = encryptor;
        this.academyService = academyService;
        this.approvals = approvals;
        this.billing = billing;
        this.em = em;
    }

    // ---------------------------------------------------------------- reading

    @Transactional(readOnly = true)
    public Map<String, Object> pipeline() {
        LocalDate today = LocalDate.now();
        List<Map<String, Object>> leads = new ArrayList<>();
        jdbc.query("""
                SELECT l.*, p.display_name AS plan_name, p.monthly_price,
                       h.decision AS approval_decision
                FROM hq_leads l LEFT JOIN billing_plans p ON p.code = l.plan_code LEFT JOIN hq_requests h ON h.id = l.approval_id
                WHERE l.stage IN ('LEAD', 'DEMO') ORDER BY l.created_at DESC""", rs -> {
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("id", rs.getObject("id", UUID.class));
            m.put("stage", rs.getString("stage"));
            m.put("name", rs.getString("name"));
            m.put("owner", rs.getString("owner_name"));
            m.put("city", rs.getString("city"));
            m.put("type", rs.getString("type"));
            m.put("planCode", rs.getString("plan_code"));
            m.put("planName", rs.getString("plan_name"));
            m.put("planPrice", rs.getBigDecimal("monthly_price"));
            m.put("est", rs.getInt("est_students"));
            m.put("demoDays", rs.getInt("demo_days"));
            LocalDate started = rs.getObject("demo_started_on", LocalDate.class);
            int total = rs.getInt("demo_days");
            long dayIn = started == null ? 0 : Math.min(total, ChronoUnit.DAYS.between(started, today));
            boolean done = "DEMO".equals(rs.getString("stage")) && (rs.getBoolean("demo_done") || dayIn >= total);
            m.put("dayIn", dayIn);
            m.put("daysLeft", Math.max(0, total - dayIn));
            m.put("demoDone", done);
            m.put("academyId", rs.getObject("academy_id"));
            Map<String, Object> checks = new LinkedHashMap<>();
            checks.put("details", rs.getBoolean("v_details"));
            checks.put("gateway", rs.getBoolean("v_gateway"));
            checks.put("approved", rs.getBoolean("approved"));
            String d = rs.getString("approval_decision");
            checks.put("approval", rs.getObject("approval_id") == null ? "none" : d == null ? "pending" : d);
            m.put("checks", checks);
            leads.add(m);
        });

        // Academies that went live in the last 30 days, whether or not they came through here.
        List<Map<String, Object>> live = jdbc.queryForList("""
                SELECT a.id AS "academyId", a.name, a.owner_name AS owner, a.city, a.go_live_on AS "since", a.plan AS "planCode",
                       p.display_name AS "planName",
                       (SELECT count(*) FROM academy_memberships m WHERE m.academy_id = a.id AND m.role_type = 'STUDENT' AND m.status = 'ACTIVE') AS students
                FROM academies a LEFT JOIN billing_plans p ON p.code = a.plan
                WHERE a.closed_at IS NULL AND a.demo_ends_on IS NULL AND a.go_live_on >= current_date - 30
                ORDER BY a.go_live_on DESC""");

        Map<String, Object> out = new LinkedHashMap<>();
        out.put("leads", leads.stream().filter(l -> "LEAD".equals(l.get("stage"))).toList());
        out.put("demos", leads.stream().filter(l -> "DEMO".equals(l.get("stage"))).toList());
        out.put("live", live);
        BigDecimal potential = BigDecimal.ZERO;
        for (var l : leads) {
            if (l.get("planPrice") != null) potential = potential.add((BigDecimal) l.get("planPrice"));
        }
        out.put("potentialMrr", potential);
        return out;
    }

    // ---------------------------------------------------------------- registering

    @Transactional
    public UUID createLead(Map<String, Object> b) {
        String name = s(b, "name"), type = s(b, "type"), aemail = s(b, "aemail"), aphone = s(b, "aphone");
        String a1 = s(b, "a1"), city = s(b, "city"), state = s(b, "state"), pin = s(b, "pin");
        String owner = s(b, "owner"), ophone = s(b, "ophone"), oemail = s(b, "oemail"), plan = s(b, "plan");
        int est = intOf(b.get("est"));
        int demoDays = intOf(b.get("demo"));

        if (name.length() < 3) throw new BadRequestException("Enter the academy name.");
        if (!EMAIL.matcher(aemail).matches()) throw new BadRequestException("Enter a valid academy email address.");
        if (!MOBILE.matcher(aphone).matches()) throw new BadRequestException("Enter the academy phone as a 10-digit mobile number.");
        if (a1.length() < 3) throw new BadRequestException("Enter address line 1.");
        if (city.length() < 2) throw new BadRequestException("Enter the city.");
        if (state.length() < 2) throw new BadRequestException("Enter the state.");
        if (!pin.matches("^\\d{6}$")) throw new BadRequestException("Enter a 6-digit PIN code.");
        if (owner.length() < 2) throw new BadRequestException("Enter the owner's name.");
        if (!MOBILE.matcher(ophone).matches()) throw new BadRequestException("Enter the owner's 10-digit mobile number.");
        if (!EMAIL.matcher(oemail).matches()) throw new BadRequestException("Enter a valid owner email address.");
        if (est <= 0) throw new BadRequestException("Enter the expected number of students.");
        if (demoDays < 15 || demoDays > 90) throw new BadRequestException("The demo period is a whole number of days, from 15 to 90 (3 months).");
        if (jdbc.queryForObject("SELECT count(*) FROM billing_plans WHERE code = ? AND active", Integer.class, plan) == 0) {
            throw new BadRequestException("Choose a plan.");
        }
        Integer dup = jdbc.queryForObject("""
                SELECT (SELECT count(*) FROM academies WHERE lower(name) = lower(?)) + (SELECT count(*) FROM hq_leads WHERE lower(name) = lower(?) AND stage <> 'DROPPED')""",
                Integer.class, name, name);
        if (dup != null && dup > 0) throw new ConflictException("An academy with this name already exists.");
        Integer emailDup = jdbc.queryForObject("""
                SELECT (SELECT count(*) FROM academies WHERE lower(email) = lower(?)) + (SELECT count(*) FROM hq_leads WHERE lower(academy_email) = lower(?) AND stage <> 'DROPPED')""",
                Integer.class, aemail, aemail);
        if (emailDup != null && emailDup > 0) throw new ConflictException("This academy email is already registered.");

        List<Map<String, Object>> banks = banks(b.get("accts"), b.get("primary"));
        UUID id = UUID.randomUUID();
        jdbc.update("""
                INSERT INTO hq_leads (id, name, type, academy_email, academy_phone, address_line1, address_line2, landmark, city, district, state, country, pin,
                                      owner_name, owner_phone, owner_email, plan_code, est_students, demo_days, banks)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
                id, name, type, aemail, aphone, a1, nullIfBlank(s(b, "a2")), nullIfBlank(s(b, "landmark")), city, nullIfBlank(s(b, "district")), state,
                s(b, "country").isEmpty() ? "India" : s(b, "country"), pin, owner, ophone, oemail, plan, est, demoDays, write(banks));
        audit.log("onboarding", "Registered " + name + " as a lead");
        return id;
    }

    /** Validates up to two bank accounts and returns them ready to store, with the number encrypted. */
    private List<Map<String, Object>> banks(Object raw, Object primaryIdx) {
        List<?> list = raw instanceof List<?> l ? l : List.of();
        List<Map<String, Object>> out = new ArrayList<>();
        java.util.Set<String> numbers = new java.util.HashSet<>();
        int primary = intOf(primaryIdx);
        for (int i = 0; i < Math.min(2, list.size()); i++) {
            @SuppressWarnings("unchecked") Map<String, Object> a = (Map<String, Object>) list.get(i);
            String holder = s(a, "holder"), acct = s(a, "acct"), ifsc = s(a, "ifsc");
            boolean any = !holder.isEmpty() || !acct.isEmpty() || !ifsc.isEmpty();
            if (!any) {
                if (i == 0) throw new BadRequestException("Add the first bank account: holder name, 9 to 18 digit number and IFSC.");
                continue;
            }
            if (holder.length() < 3 || !ACCOUNT.matcher(acct).matches() || !IFSC.matcher(ifsc).matches()) {
                throw new BadRequestException(i == 0 ? "Add the first bank account: holder name, 9 to 18 digit number and IFSC." : "Finish bank account " + (i + 1) + " or clear it.");
            }
            if (!numbers.add(acct)) throw new BadRequestException("The same account number is used twice.");
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("bank", s(a, "bank").isEmpty() ? "Other" : s(a, "bank"));
            m.put("type", "Savings".equals(s(a, "type")) ? "Savings" : "Current");
            m.put("gateway", List.of("Razorpay", "Cashfree", "PayU").contains(s(a, "gw")) ? s(a, "gw") : "Razorpay");
            m.put("holder", holder);
            m.put("last4", acct.substring(acct.length() - 4));
            m.put("enc", encryptor.encrypt(acct));
            m.put("ifsc", ifsc.toUpperCase());
            m.put("primary", i == primary);
            out.add(m);
        }
        if (out.stream().noneMatch(m -> Boolean.TRUE.equals(m.get("primary")))) out.get(0).put("primary", true);
        return out;
    }

    // ---------------------------------------------------------------- the pipeline

    /** Creates the real academy and the owner's login. Returns the credentials to give the owner. */
    @Transactional
    public Map<String, Object> startDemo(UUID id) {
        var l = lead(id);
        if (!"LEAD".equals(l.get("stage"))) throw new ConflictException("This one is already in a demo.");
        String name = (String) l.get("name"), owner = (String) l.get("owner_name");
        String username = uniqueUsername(owner);
        OnboardAcademyResponse res = academyService.onboardAcademy(new OnboardAcademyRequest(
                name, AcademyCategory.valueOf(HqAcademies.categoryOf((String) l.get("type"))), null,
                l.get("address_line1").toString(), (String) l.get("city"), (String) l.get("state"), (String) l.get("academy_phone"), (String) l.get("academy_email"),
                (String) l.get("plan_code"), username, owner, (String) l.get("owner_phone"), (String) l.get("owner_email")));
        UUID academyId = res.academy().id();
        // The academy was saved through JPA; flush so the JDBC statements below can see the row.
        em.flush();
        int days = ((Number) l.get("demo_days")).intValue();
        jdbc.update("""
                UPDATE academies SET demo_ends_on = ?, go_live_on = NULL, address_line2 = ?, landmark = ?, district = ?, country = ?, pin_code = ?,
                       owner_name = ?, owner_phone = ?, owner_email = ?, updated_at = now() WHERE id = ?""",
                LocalDate.now().plusDays(days), l.get("address_line2"), l.get("landmark"), l.get("district"), l.get("country"), l.get("pin"),
                owner, l.get("owner_phone"), l.get("owner_email"), academyId);
        for (var bank : read((String) l.get("banks"))) {
            jdbc.update("""
                    INSERT INTO academy_bank_accounts (academy_id, bank, account_type, holder, account_last4, account_enc, ifsc, is_primary, gateway)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)""", academyId, bank.get("bank"), bank.get("type"), bank.get("holder"), bank.get("last4"), bank.get("enc"),
                    bank.get("ifsc"), bank.get("primary"), bank.get("gateway"));
        }
        jdbc.update("UPDATE hq_leads SET stage = 'DEMO', academy_id = ?, demo_started_on = current_date WHERE id = ?", academyId, id);
        audit.log("onboarding", academyId, "Started a " + (days % 30 == 0 ? (days / 30) + "-month" : days + "-day") + " demo for " + name);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("academyId", academyId);
        out.put("username", res.adminUsername());
        out.put("password", res.adminTemporaryPassword());
        return out;
    }

    @Transactional
    public void finishDemo(UUID id) {
        var l = lead(id);
        if (!"DEMO".equals(l.get("stage"))) throw new BadRequestException("This academy is not in a demo.");
        jdbc.update("UPDATE hq_leads SET demo_done = TRUE WHERE id = ?", id);
        audit.log("onboarding", (UUID) l.get("academy_id"), (String) l.get("name") + " demo marked complete");
    }

    /** The "details validated" check: required fields, formats, and no duplicate academy. */
    @Transactional
    public void validate(UUID id) {
        var l = lead(id);
        List<String> issues = new ArrayList<>();
        for (String k : new String[]{"name", "owner_name", "city", "academy_phone", "academy_email", "address_line1", "owner_email"}) {
            if (l.get(k) == null || l.get(k).toString().trim().length() < 2) issues.add(k.replace('_', ' ') + " is missing");
        }
        if (!MOBILE.matcher(String.valueOf(l.get("owner_phone"))).matches()) issues.add("owner mobile is not valid");
        if (!EMAIL.matcher(String.valueOf(l.get("owner_email"))).matches()) issues.add("owner email is not valid");
        Integer dup = jdbc.queryForObject("""
                SELECT (SELECT count(*) FROM academies WHERE lower(name) = lower(?) AND id IS DISTINCT FROM ?) + (SELECT count(*) FROM hq_leads WHERE lower(name) = lower(?) AND id <> ? AND stage <> 'DROPPED')""",
                Integer.class, l.get("name"), l.get("academy_id"), l.get("name"), id);
        if (dup != null && dup > 0) issues.add("an academy with this name already exists");
        if (!issues.isEmpty()) throw new BadRequestException("Validation failed: " + issues.get(0));
        jdbc.update("UPDATE hq_leads SET v_details = TRUE WHERE id = ?", id);
        audit.log("onboarding", (UUID) l.get("academy_id"), "Validated details of " + l.get("name"));
    }

    /** The "payment gateway" check passes once the primary bank account has a gateway AND merchant ID mapped. */
    @Transactional
    public void verifyGateway(UUID id) {
        var l = lead(id);
        if (l.get("academy_id") == null) throw new BadRequestException("Start the demo first: the academy's bank accounts exist from then.");
        Integer mapped = jdbc.queryForObject("""
                SELECT count(*) FROM academy_bank_accounts WHERE academy_id = ? AND is_primary AND gateway IS NOT NULL AND merchant_id IS NOT NULL""",
                Integer.class, l.get("academy_id"));
        if (mapped == null || mapped == 0) {
            throw new BadRequestException("Map the payment gateway on the primary bank account first: open the academy in Entities and use Map gateway.");
        }
        jdbc.update("UPDATE hq_leads SET v_gateway = TRUE WHERE id = ?", id);
        audit.log("onboarding", (UUID) l.get("academy_id"), "Verified the payment gateway of " + l.get("name"));
    }

    @Transactional
    public void sendForApproval(UUID id) {
        var l = lead(id);
        if (!Boolean.TRUE.equals(l.get("v_details")) || !Boolean.TRUE.equals(l.get("v_gateway"))) {
            throw new BadRequestException("Validate the details and verify the gateway first.");
        }
        if (l.get("approval_id") != null && Boolean.TRUE.equals(jdbc.queryForObject(
                "SELECT decision IS NULL OR decision = 'approved' FROM hq_requests WHERE id = ?", Boolean.class, l.get("approval_id")))) {
            throw new ConflictException("This academy already has an activation request.");
        }
        UUID req = approvals.create("ACADEMY_ACTIVATION", (UUID) l.get("academy_id"), "Owleo HQ", "Activate " + l.get("name") + " after demo",
                List.of(List.of("Plan", String.valueOf(l.get("plan_code"))), List.of("Owner", String.valueOf(l.get("owner_name")))), Map.of(), 0, "lead", id.toString());
        jdbc.update("UPDATE hq_leads SET approval_id = ?, approved = FALSE WHERE id = ?", req, id);
        audit.log("onboarding", (UUID) l.get("academy_id"), "Sent " + l.get("name") + " for activation approval");
    }

    @EventListener
    @Transactional
    public void onRequestDecided(HqApprovals.RequestDecided e) {
        if (!"ACADEMY_ACTIVATION".equals(e.type()) || !"lead".equals(e.refKind())) return;
        if ("approved".equals(e.decision())) {
            jdbc.update("UPDATE hq_leads SET approved = TRUE WHERE id = ?", UUID.fromString(e.refId()));
        }
    }

    @Transactional
    public void goLive(UUID id) {
        var l = lead(id);
        if (!"DEMO".equals(l.get("stage"))) throw new BadRequestException("This academy is not in a demo.");
        boolean ok = Boolean.TRUE.equals(l.get("v_details")) && Boolean.TRUE.equals(l.get("v_gateway")) && Boolean.TRUE.equals(l.get("approved"));
        if (!ok) throw new BadRequestException("Finish validation, the payment gateway and approval first.");
        UUID academyId = (UUID) l.get("academy_id");
        jdbc.update("UPDATE academies SET demo_ends_on = NULL, go_live_on = current_date, updated_at = now() WHERE id = ?", academyId);
        jdbc.update("UPDATE hq_leads SET stage = 'LIVE', live_since = current_date WHERE id = ?", id);
        // Raise this month's bill now if there is not one, so the setup fee is not missed until next month.
        billing.generate(YearMonth.now().toString(), academyId);
        audit.log("onboarding", academyId, l.get("name") + " went live");
    }

    // ---------------------------------------------------------------- helpers

    private Map<String, Object> lead(UUID id) {
        return jdbc.queryForList("SELECT * FROM hq_leads WHERE id = ?", id).stream().findFirst().orElseThrow(() -> new ResourceNotFoundException("Not found."));
    }

    private String uniqueUsername(String owner) {
        String base = owner.toLowerCase().replaceAll("[^a-z0-9]+", "");
        if (base.isEmpty()) base = "owner";
        for (int i = 0; i < 50; i++) {
            String u = base + (100 + (int) (Math.random() * 900));
            Integer n = jdbc.queryForObject("SELECT count(*) FROM users WHERE username = ?", Integer.class, u);
            if (n != null && n == 0) return u;
        }
        return base + System.currentTimeMillis() % 100000;
    }

    private List<Map<String, Object>> read(String s) {
        try {
            return json.readValue(s, new TypeReference<List<Map<String, Object>>>() { });
        } catch (Exception e) {
            throw new IllegalStateException(e);
        }
    }

    private String write(Object o) {
        try {
            return json.writeValueAsString(o);
        } catch (Exception e) {
            throw new IllegalStateException(e);
        }
    }

    private static String s(Map<String, Object> b, String k) {
        Object v = b.get(k);
        return v == null ? "" : v.toString().trim();
    }

    private static int intOf(Object o) {
        try {
            return o == null ? 0 : Integer.parseInt(o.toString().trim());
        } catch (NumberFormatException e) {
            return 0;
        }
    }

    private static String nullIfBlank(String s) {
        return s == null || s.isBlank() ? null : s;
    }
}
