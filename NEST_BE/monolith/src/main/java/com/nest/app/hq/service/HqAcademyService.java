package com.nest.app.hq.service;

import com.nest.app.hq.HqAudit;
import com.nest.common.exception.BadRequestException;
import com.nest.common.exception.ConflictException;
import com.nest.common.exception.ResourceNotFoundException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.YearMonth;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.regex.Pattern;

/** Everything the Entities module does to one academy: read its profile, edit it, suspend it, move it
 * to another plan, and list the people and classes inside it. */
@Service
public class HqAcademyService {

    private static final Pattern EMAIL = Pattern.compile("^\\S+@\\S+\\.\\S+$");
    private static final Pattern MOBILE = Pattern.compile("^[6-9]\\d{9}$");
    private static final Pattern PIN = Pattern.compile("^\\d{6}$");

    private final JdbcTemplate jdbc;
    private final HqAcademies academies;
    private final HqAudit audit;

    public HqAcademyService(JdbcTemplate jdbc, HqAcademies academies, HqAudit audit) {
        this.jdbc = jdbc;
        this.academies = academies;
        this.audit = audit;
    }

    private HqAcademies.Row require(UUID id) {
        return academies.one(id).orElseThrow(() -> new ResourceNotFoundException("Academy not found: " + id));
    }

    /** The full profile behind the academy drawer. */
    @Transactional(readOnly = true)
    public Map<String, Object> detail(UUID id) {
        var row = require(id);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("academy", row);

        Map<String, Object> contact = new LinkedHashMap<>();
        jdbc.query("""
                SELECT email, contact_number, address, address_line2, landmark, city, district, state, country,
                       pin_code, owner_name, owner_phone, owner_email
                FROM academies WHERE id = ?""", rs -> {
            contact.put("aemail", nz(rs.getString("email")));
            contact.put("aphone", nz(rs.getString("contact_number")));
            contact.put("a1", nz(rs.getString("address")));
            contact.put("a2", nz(rs.getString("address_line2")));
            contact.put("landmark", nz(rs.getString("landmark")));
            contact.put("city", nz(rs.getString("city")));
            contact.put("district", nz(rs.getString("district")));
            contact.put("state", nz(rs.getString("state")));
            contact.put("country", nz(rs.getString("country")));
            contact.put("pin", nz(rs.getString("pin_code")));
            contact.put("owner", nz(rs.getString("owner_name")));
            contact.put("ophone", nz(rs.getString("owner_phone")));
            contact.put("oemail", nz(rs.getString("owner_email")));
        }, id);
        out.put("contact", contact);

        out.put("history", usersByMonth(id));
        out.put("invoices", jdbc.queryForList("""
                SELECT i.id, i.period, i.total, i.due_on AS "dueOn",
                       CASE WHEN i.status = 'WAIVED' THEN 'waived'
                            WHEN COALESCE((SELECT SUM(p.amount) FROM invoice_payments p WHERE p.invoice_id = i.id), 0) >= i.total THEN 'paid'
                            WHEN i.due_on < current_date THEN 'overdue' ELSE 'due' END AS status
                FROM academy_invoices i WHERE i.academy_id = ? ORDER BY i.period DESC LIMIT 3""", id));
        out.put("banks", banks(id));
        out.put("log", audit.recent(null, id, 4));
        YearMonth next = YearMonth.now().plusMonths(1);
        out.put("renewsOn", next.atDay(1).toString());
        return out;
    }

    private List<Map<String, Object>> banks(UUID id) {
        return jdbc.queryForList("""
                SELECT id, bank, account_type AS "type", holder, account_last4 AS "last4", ifsc,
                       is_primary AS "primary", gateway, merchant_id AS "merchantId"
                FROM academy_bank_accounts WHERE academy_id = ? ORDER BY is_primary DESC, created_at""", id);
    }

    /** Members counted cumulatively at the end of each of the last 12 months. */
    private long[] usersByMonth(UUID id) {
        List<String> months = HqSeries.months();
        long[] out = new long[months.size()];
        jdbc.query("""
                SELECT to_char(created_at, 'YYYY-MM') AS m, count(*) AS c FROM academy_memberships
                WHERE academy_id = ? AND status = 'ACTIVE' GROUP BY 1""", rs -> {
            String m = rs.getString("m");
            int idx = m.compareTo(months.get(0)) < 0 ? 0 : months.indexOf(m);
            if (idx >= 0) {
                out[idx] += rs.getLong("c");
            }
        }, id);
        for (int i = 1; i < out.length; i++) {
            out[i] += out[i - 1];
        }
        return out;
    }

    @Transactional
    public void edit(UUID id, Map<String, Object> b) {
        var cur = require(id);
        String name = s(b, "name"), type = s(b, "type"), owner = s(b, "owner");
        String aemail = s(b, "aemail"), aphone = s(b, "aphone"), a1 = s(b, "a1"), a2 = s(b, "a2");
        String landmark = s(b, "landmark"), city = s(b, "city"), district = s(b, "district"), state = s(b, "state");
        String country = s(b, "country"), pin = s(b, "pin"), ophone = s(b, "ophone"), oemail = s(b, "oemail");

        if (name.length() < 3) throw new BadRequestException("Enter the academy name.");
        if (!EMAIL.matcher(aemail).matches()) throw new BadRequestException("Enter a valid academy email address.");
        if (!MOBILE.matcher(aphone).matches()) throw new BadRequestException("Enter a 10-digit mobile number for the academy.");
        if (a1.length() < 3) throw new BadRequestException("Enter address line 1.");
        if (city.length() < 2) throw new BadRequestException("Enter the city.");
        if (state.length() < 2) throw new BadRequestException("Enter the state.");
        if (!PIN.matcher(pin).matches()) throw new BadRequestException("Enter a 6-digit PIN code.");
        if (owner.length() < 2) throw new BadRequestException("Enter the owner name.");
        if (!MOBILE.matcher(ophone).matches()) throw new BadRequestException("Enter a 10-digit mobile number for the owner.");
        if (!EMAIL.matcher(oemail).matches()) throw new BadRequestException("Enter a valid owner email address.");

        Integer clash = jdbc.queryForObject("""
                SELECT count(*) FROM academies WHERE id <> ? AND lower(name) = lower(?) AND lower(city) = lower(?)""",
                Integer.class, id, name, city);
        if (clash != null && clash > 0) {
            throw new ConflictException("An academy named '" + name + "' already exists in " + city + ".");
        }

        List<String> changed = new ArrayList<>();
        if (!cur.name().equals(name)) changed.add("name");
        if (!cur.type().equals(type)) changed.add("type");
        if (!owner.equals(nz(cur.owner()))) changed.add("owner");
        Map<String, Object> old = (Map<String, Object>) detail(id).get("contact");
        for (var e : Map.of("aemail", "academy email", "aphone", "academy phone", "ophone", "owner phone", "oemail", "owner email").entrySet()) {
            if (!nz((String) old.get(e.getKey())).equals(b.get(e.getKey()) == null ? "" : b.get(e.getKey()).toString().trim())) {
                changed.add(e.getValue());
            }
        }
        for (String k : new String[]{"a1", "a2", "landmark", "city", "district", "state", "country", "pin"}) {
            if (!nz((String) old.get(k)).equals(s(b, k))) {
                changed.add("address");
                break;
            }
        }
        if (changed.isEmpty()) {
            return;
        }

        jdbc.update("""
                UPDATE academies SET name = ?, category = ?, owner_name = ?, email = ?, contact_number = ?,
                       address = ?, address_line2 = ?, landmark = ?, city = ?, district = ?, state = ?,
                       country = ?, pin_code = ?, owner_phone = ?, owner_email = ?, updated_at = now()
                WHERE id = ?""",
                name, HqAcademies.categoryOf(type), owner, aemail, aphone, a1, blankNull(a2), blankNull(landmark), city,
                blankNull(district), state, country.isEmpty() ? "India" : country, pin, ophone, oemail, id);
        audit.log("academies", id, "Edited " + String.join(", ", changed) + " · " + name);
    }

    @Transactional
    public void setSuspended(UUID id, boolean suspended) {
        var cur = require(id);
        jdbc.update("UPDATE academies SET status = ?, updated_at = now() WHERE id = ?", suspended ? "SUSPENDED" : "ACTIVE", id);
        audit.log("academies", id, (suspended ? "Suspended " : "Reactivated ") + cur.name());
    }

    /** Moves an academy to another plan from its next renewal. Refuses a plan whose student limit the
     * academy already exceeds: silently downgrading below usage would just create an overdue upsell. */
    @Transactional
    public void changePlan(UUID id, String planCode, String reason) {
        var cur = require(id);
        Map<String, Object> plan = jdbc.queryForList(
                "SELECT code, display_name, max_students FROM billing_plans WHERE code = ? AND active", planCode)
                .stream().findFirst().orElseThrow(() -> new BadRequestException("Unknown plan: " + planCode));
        if (planCode.equals(cur.plan())) {
            throw new BadRequestException("This academy is already on " + plan.get("display_name") + ".");
        }
        Integer max = (Integer) plan.get("max_students");
        if (max != null && cur.students() > max) {
            throw new BadRequestException(cur.students() + " students is over the " + max + " limit of " + plan.get("display_name") + ".");
        }
        jdbc.update("UPDATE academies SET plan = ?, updated_at = now() WHERE id = ?", planCode, id);
        audit.log("academies", id, "Plan changed from " + nz(cur.planName()) + " to " + plan.get("display_name")
                + (reason == null || reason.isBlank() ? "" : " (" + reason + ")") + " · " + cur.name());
    }

    /** The lists behind the drill-down drawer: students, trainers, courses or batches. */
    @Transactional(readOnly = true)
    public List<Map<String, Object>> people(UUID id, String kind, String q) {
        require(id);
        String like = q == null || q.isBlank() ? null : "%" + q.trim().toLowerCase() + "%";
        return switch (kind) {
            case "students" -> jdbc.queryForList("""
                    SELECT m.id, u.full_name AS name, m.created_at AS "joined",
                           COALESCE((SELECT string_agg(DISTINCT c.name, ', ') FROM batch_members bm
                                     JOIN batches b ON b.id = bm.batch_id JOIN courses c ON c.id = b.course_id
                                     WHERE bm.membership_id = m.id), '') AS courses,
                           (SELECT round(100.0 * count(*) FILTER (WHERE at.status = 'PRESENT') / NULLIF(count(*), 0))
                              FROM attendance at JOIN class_instances ci ON ci.id = at.class_instance_id
                             WHERE at.membership_id = m.id AND ci.date >= current_date - 60) AS attendance,
                           (SELECT COALESCE(SUM(GREATEST(0, fs.amount_due - COALESCE((SELECT SUM(ft.amount_paid) FROM fee_transactions ft
                                     WHERE ft.membership_id = fs.membership_id AND ft.course_id = fs.course_id AND ft.period = fs.period
                                       AND ft.reversal_of_transaction_id IS NULL), 0))), 0)
                              FROM fee_slips fs WHERE fs.membership_id = m.id AND fs.generated_at >= now() - interval '40 days') AS "feeDue"
                    FROM academy_memberships m JOIN users u ON u.id = m.user_id
                    WHERE m.academy_id = ? AND m.role_type = 'STUDENT' AND m.status = 'ACTIVE'
                      AND (?::text IS NULL OR lower(u.full_name) LIKE ?)
                    ORDER BY u.full_name""", id, like, like);
            case "trainers" -> jdbc.queryForList("""
                    SELECT m.id, u.full_name AS name, u.years_of_experience AS "years",
                           COALESCE((SELECT string_agg(DISTINCT c.name, ', ') FROM trainer_course_batches t
                                     JOIN courses c ON c.id = t.course_id WHERE t.membership_id = m.id), '') AS spec,
                           (SELECT count(DISTINCT t.batch_id) FROM trainer_course_batches t WHERE t.membership_id = m.id AND t.batch_id IS NOT NULL) AS batches,
                           (SELECT count(DISTINCT bm.membership_id) FROM batch_members bm
                              JOIN trainer_course_batches t ON t.batch_id = bm.batch_id WHERE t.membership_id = m.id) AS students
                    FROM academy_memberships m JOIN users u ON u.id = m.user_id
                    WHERE m.academy_id = ? AND m.role_type = 'TRAINER' AND m.status = 'ACTIVE'
                      AND (?::text IS NULL OR lower(u.full_name) LIKE ?)
                    ORDER BY u.full_name""", id, like, like);
            case "courses" -> jdbc.queryForList("""
                    SELECT c.id, c.name, c.default_fee AS fee, c.category,
                           (SELECT count(*) FROM batches b WHERE b.course_id = c.id AND b.status = 'ACTIVE') AS batches,
                           (SELECT count(DISTINCT bm.membership_id) FROM batch_members bm JOIN batches b ON b.id = bm.batch_id WHERE b.course_id = c.id) AS enrolled
                    FROM courses c WHERE c.academy_id = ? AND c.status = 'ACTIVE'
                      AND (?::text IS NULL OR lower(c.name) LIKE ?)
                    ORDER BY c.name""", id, like, like);
            case "batches" -> jdbc.queryForList("""
                    SELECT b.id, b.name, c.name AS course, b.status, b.start_date AS "start", b.end_date AS "end",
                           COALESCE((SELECT string_agg(u.full_name, ', ') FROM batch_trainers bt
                                     JOIN academy_memberships tm ON tm.id = bt.trainer_membership_id
                                     JOIN users u ON u.id = tm.user_id WHERE bt.batch_id = b.id), '') AS trainers,
                           (SELECT count(*) FROM batch_members bm WHERE bm.batch_id = b.id) AS enrolled,
                           COALESCE((SELECT string_agg(DISTINCT s.day_of_week, ', ') FROM schedules s
                                     WHERE s.batch_id = b.id AND (s.effective_to IS NULL OR s.effective_to >= current_date)), '') AS days
                    FROM batches b JOIN courses c ON c.id = b.course_id
                    WHERE c.academy_id = ? AND (?::text IS NULL OR lower(b.name || ' ' || c.name) LIKE ?)
                    ORDER BY c.name, b.name""", id, like, like);
            default -> throw new BadRequestException("Unknown list: " + kind);
        };
    }

    @Transactional
    public void mapGateway(UUID academyId, UUID bankId, String provider, String merchantId) {
        if (!List.of("Razorpay", "Cashfree", "PayU").contains(provider)) {
            throw new BadRequestException("Choose Razorpay, Cashfree or PayU.");
        }
        if (merchantId == null || !merchantId.matches("^[A-Za-z0-9_\\-]{6,30}$")) {
            throw new BadRequestException("Enter the merchant ID: 6 to 30 letters, numbers, - or _.");
        }
        Integer dup = jdbc.queryForObject("""
                SELECT count(*) FROM academy_bank_accounts WHERE academy_id = ? AND id <> ? AND gateway = ? AND merchant_id = ?""",
                Integer.class, academyId, bankId, provider, merchantId);
        if (dup != null && dup > 0) {
            throw new ConflictException("This merchant ID is already mapped to the other account.");
        }
        int n = jdbc.update("UPDATE academy_bank_accounts SET gateway = ?, merchant_id = ? WHERE id = ? AND academy_id = ?",
                provider, merchantId, bankId, academyId);
        if (n == 0) {
            throw new ResourceNotFoundException("Bank account not found.");
        }
        audit.log("academies", academyId, provider + " mapped to a bank account · " + require(academyId).name());
    }

    private static String s(Map<String, Object> b, String k) {
        Object v = b.get(k);
        return v == null ? "" : v.toString().trim();
    }

    private static String nz(String s) {
        return s == null ? "" : s;
    }

    private static String blankNull(String s) {
        return s == null || s.isBlank() ? null : s;
    }
}
