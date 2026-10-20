package com.nest.app.hq.service;

import com.nest.common.crypto.PiiEncryptor;
import com.nest.common.exception.ResourceNotFoundException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

import java.math.BigDecimal;
import java.sql.Timestamp;
import java.time.LocalDate;
import java.time.YearMonth;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

/**
 * One academy's students as HQ sees them: who is behind on fees or attendance, who has agreed to
 * marketing, what each is interested in, and the insights those add up to. Contact details are never
 * returned here; the profile drawer reveals them through the Users endpoint, which logs every reveal.
 */
@Service
public class HqStudents {

    private final JdbcTemplate jdbc;
    private final PiiEncryptor encryptor;

    public HqStudents(JdbcTemplate jdbc, PiiEncryptor encryptor) {
        this.jdbc = jdbc;
        this.encryptor = encryptor;
    }

    private Integer age(Object dobEnc) {
        if (dobEnc == null || dobEnc.toString().isBlank()) return null;
        try {
            return (int) java.time.temporal.ChronoUnit.YEARS.between(LocalDate.parse(encryptor.decrypt(dobEnc.toString())), LocalDate.now());
        } catch (Exception e) {
            return null;
        }
    }

    private static final String CORE = """
            SELECT m.id AS membership_id, u.id AS user_id, u.full_name, u.dob, u.marketing_consent, u.last_seen_at, m.joining_date,
                   COALESCE((SELECT array_agg(DISTINCT c.name ORDER BY c.name) FROM batch_members bm JOIN batches b ON b.id = bm.batch_id JOIN courses c ON c.id = b.course_id WHERE bm.membership_id = m.id), '{}') AS courses,
                   COALESCE((SELECT array_agg(DISTINCT c.category) FROM batch_members bm JOIN batches b ON b.id = bm.batch_id JOIN courses c ON c.id = b.course_id WHERE bm.membership_id = m.id), '{}') AS cats,
                   (SELECT count(*) FILTER (WHERE a.status = 'PRESENT') FROM attendance a WHERE a.membership_id = m.id AND a.marked_at > now() - interval '60 days') AS present,
                   (SELECT count(*) FROM attendance a WHERE a.membership_id = m.id AND a.marked_at > now() - interval '60 days') AS marked,
                   COALESCE((SELECT sum(GREATEST(0, s.amount_due - COALESCE((SELECT sum(t.amount_paid) FROM fee_transactions t WHERE t.membership_id = s.membership_id AND t.course_id = s.course_id AND t.period = s.period AND t.reversal_of_transaction_id IS NULL), 0)))
                              FROM fee_slips s WHERE s.membership_id = m.id), 0) AS due,
                   COALESCE((SELECT max(s.period) FROM fee_slips s WHERE s.membership_id = m.id AND s.amount_due > COALESCE((SELECT sum(t.amount_paid) FROM fee_transactions t WHERE t.membership_id = s.membership_id AND t.course_id = s.course_id AND t.period = s.period AND t.reversal_of_transaction_id IS NULL), 0)), '') AS oldest_unpaid
            FROM academy_memberships m JOIN users u ON u.id = m.user_id
            WHERE m.academy_id = ? AND m.role_type = 'STUDENT' AND m.status = 'ACTIVE'""";

    private List<Map<String, Object>> students(UUID academy) {
        String thisMonth = YearMonth.now().toString();
        List<Map<String, Object>> out = new ArrayList<>();
        for (var r : jdbc.queryForList(CORE, academy)) {
            int marked = ((Number) r.get("marked")).intValue();
            Integer att = marked == 0 ? null : (int) Math.round(((Number) r.get("present")).doubleValue() / marked * 100);
            BigDecimal due = (BigDecimal) r.get("due");
            String unpaid = (String) r.get("oldest_unpaid");
            String fee = due.signum() == 0 ? "paid" : (unpaid.compareTo(thisMonth) < 0 ? "overdue" : "due");
            Integer age = age(r.get("dob"));
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("id", r.get("membership_id"));
            m.put("userId", r.get("user_id"));
            m.put("name", r.get("full_name"));
            m.put("age", age);
            m.put("minor", age != null && age < 18);
            m.put("courses", asList(r.get("courses")));
            m.put("cats", asList(r.get("cats")));
            m.put("att", att);
            m.put("fee", fee);
            m.put("due", due);
            m.put("consent", r.get("marketing_consent"));
            m.put("joined", r.get("joining_date"));
            m.put("lastSeen", r.get("last_seen_at") == null ? null : ((Timestamp) r.get("last_seen_at")).toInstant());
            out.add(m);
        }
        return out;
    }

    private static List<String> asList(Object arr) {
        try {
            return new ArrayList<>(List.of((String[]) ((java.sql.Array) arr).getArray()));
        } catch (Exception e) {
            return List.of();
        }
    }

    public Map<String, Object> list(UUID academy, String q, String flt, int limit, int offset) {
        List<Map<String, Object>> all = students(academy);
        String needle = q == null ? "" : q.trim().toLowerCase();
        int due = 0, low = 0, mkt = 0, minor = 0;
        List<Map<String, Object>> shown = new ArrayList<>();
        for (var s : all) {
            boolean isDue = !"paid".equals(s.get("fee")), isLow = s.get("att") != null && (Integer) s.get("att") < 70;
            boolean isMkt = Boolean.TRUE.equals(s.get("consent")), isMinor = Boolean.TRUE.equals(s.get("minor"));
            if (isDue) due++;
            if (isLow) low++;
            if (isMkt) mkt++;
            if (isMinor) minor++;
            boolean keep = switch (flt == null ? "all" : flt) {
                case "due" -> isDue;
                case "low" -> isLow;
                case "mkt" -> isMkt;
                case "minor" -> isMinor;
                default -> true;
            };
            if (!keep) continue;
            if (!needle.isEmpty() && !(s.get("name") + " " + String.join(" ", (List<String>) s.get("courses"))).toLowerCase().contains(needle)) continue;
            shown.add(s);
        }
        shown.sort(Comparator.comparing(s -> ((String) s.get("name")).toLowerCase()));
        int total = shown.size();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("items", shown.subList(Math.min(offset, total), Math.min(offset + limit, total)));
        out.put("total", total);
        out.put("counts", Map.of("all", all.size(), "due", due, "low", low, "mkt", mkt, "minor", minor));
        out.put("academies", jdbc.queryForList("SELECT id, name FROM academies WHERE closed_at IS NULL ORDER BY name"));
        return out;
    }

    public Map<String, Object> insights(UUID academy) {
        List<Map<String, Object>> all = students(academy);
        int n = all.size();
        int[] bands = new int[5];
        Map<String, Integer> courses = new HashMap<>(), cats = new HashMap<>();
        int attN = 0, attSum = 0, paid = 0, ready = 0, risk = 0;
        for (var s : all) {
            Integer a = (Integer) s.get("age");
            if (a != null) bands[a <= 9 ? 0 : a <= 13 ? 1 : a <= 17 ? 2 : a <= 25 ? 3 : 4]++;
            for (String c : (List<String>) s.get("courses")) courses.merge(c, 1, Integer::sum);
            for (String c : (List<String>) s.get("cats")) cats.merge(c, 1, Integer::sum);
            if (s.get("att") != null) {
                attN++;
                attSum += (Integer) s.get("att");
            }
            if ("paid".equals(s.get("fee"))) paid++;
            if (Boolean.TRUE.equals(s.get("consent"))) ready++;
            if (s.get("att") != null && (Integer) s.get("att") < 65 && !"paid".equals(s.get("fee"))) risk++;
        }
        List<Map<String, Object>> segs = new ArrayList<>();
        // Cross-sell: the art form the academy teaches that the fewest of its students are in.
        var offered = jdbc.queryForList("SELECT DISTINCT category FROM courses WHERE academy_id = ? AND status = 'ACTIVE'", String.class, academy);
        String best = null;
        int bestN = 0;
        for (String cat : offered) {
            int outside = (int) all.stream().filter(s -> !((List<String>) s.get("cats")).contains(cat) && !((List<String>) s.get("cats")).isEmpty()).count();
            if (outside > bestN) {
                bestN = outside;
                best = cat;
            }
        }
        if (best != null && n > 0) segs.add(Map.of("tone", "blue", "head", HqAcademies.typeLabel(best) + " cross-sell", "text", bestN + " students are enrolled in other art forms and could be offered " + HqAcademies.typeLabel(best), "interest", HqAcademies.typeLabel(best)));
        segs.add(Map.of("tone", "red", "head", "Retention risk", "text", risk + " students have low attendance and pending fees", "interest", ""));
        segs.add(Map.of("tone", "green", "head", "Ready for ads", "text", ready + " profiles have marketing consent (" + (n == 0 ? 0 : Math.round(ready * 100.0 / n)) + "%)", "interest", ""));

        Map<String, Object> out = new LinkedHashMap<>();
        out.put("students", n);
        out.put("avgAttendance", attN == 0 ? null : Math.round(attSum / (double) attN));
        out.put("paidPct", n == 0 ? null : Math.round(paid * 100.0 / n));
        out.put("withDues", n - paid);
        out.put("consentPct", n == 0 ? null : Math.round(ready * 100.0 / n));
        out.put("consent", ready);
        out.put("bands", List.of(Map.of("label", "6–9", "v", bands[0]), Map.of("label", "10–13", "v", bands[1]), Map.of("label", "14–17", "v", bands[2]), Map.of("label", "18–25", "v", bands[3]), Map.of("label", "26+", "v", bands[4])));
        out.put("courses", top(courses, 6));
        out.put("interests", top(cats.entrySet().stream().collect(java.util.stream.Collectors.toMap(e -> HqAcademies.typeLabel(e.getKey()), Map.Entry::getValue, Integer::sum)), 8));
        out.put("segments", segs);
        return out;
    }

    private static List<Map<String, Object>> top(Map<String, Integer> m, int n) {
        return m.entrySet().stream().sorted((a, b) -> b.getValue() - a.getValue()).limit(n).map(e -> Map.<String, Object>of("label", e.getKey(), "v", e.getValue())).toList();
    }

    public Map<String, Object> detail(UUID membershipId) {
        var mem = jdbc.queryForList("SELECT academy_id FROM academy_memberships WHERE id = ? AND role_type = 'STUDENT'", membershipId);
        if (mem.isEmpty()) throw new ResourceNotFoundException("Student not found");
        UUID academy = (UUID) mem.get(0).get("academy_id");
        Map<String, Object> s = students(academy).stream().filter(x -> membershipId.equals(x.get("id"))).findFirst().orElseThrow(() -> new ResourceNotFoundException("Student not found"));
        Map<String, Object> out = new LinkedHashMap<>(s);
        out.put("academy", jdbc.queryForObject("SELECT name FROM academies WHERE id = ?", String.class, academy));
        out.put("academyId", academy);
        out.put("enrolled", jdbc.queryForList("""
                SELECT c.name AS course, b.name AS batch, c.category,
                       (SELECT string_agg(tu.full_name, ', ') FROM batch_trainers bt JOIN academy_memberships tm ON tm.id = bt.trainer_membership_id JOIN users tu ON tu.id = tm.user_id WHERE bt.batch_id = b.id) AS trainer,
                       (SELECT CASE WHEN count(*) = 0 THEN NULL ELSE round(100.0 * count(*) FILTER (WHERE a.status = 'PRESENT') / count(*)) END
                          FROM attendance a JOIN class_instances ci ON ci.id = a.class_instance_id WHERE ci.batch_id = b.id AND a.membership_id = ? AND a.marked_at > now() - interval '60 days') AS att
                FROM batch_members bm JOIN batches b ON b.id = bm.batch_id JOIN courses c ON c.id = b.course_id WHERE bm.membership_id = ? ORDER BY c.name""", membershipId, membershipId));
        // Weekly attendance for the last 8 weeks, oldest first.
        List<Object> weekly = new ArrayList<>();
        for (int w = 7; w >= 0; w--) {
            var row = jdbc.queryForList("""
                    SELECT count(*) AS n, count(*) FILTER (WHERE status = 'PRESENT') AS p FROM attendance
                    WHERE membership_id = ? AND marked_at >= now() - ((? + 1) * interval '7 days') AND marked_at < now() - (? * interval '7 days')""", membershipId, w, w).get(0);
            long n = ((Number) row.get("n")).longValue();
            weekly.add(n == 0 ? null : Math.round(((Number) row.get("p")).doubleValue() / n * 100));
        }
        out.put("weekly", weekly);
        out.put("slips", jdbc.queryForList("""
                SELECT s.period, s.amount_due AS amount,
                       COALESCE((SELECT sum(t.amount_paid) FROM fee_transactions t WHERE t.membership_id = s.membership_id AND t.course_id = s.course_id AND t.period = s.period AND t.reversal_of_transaction_id IS NULL), 0) AS paid
                FROM fee_slips s WHERE s.membership_id = ? ORDER BY s.period DESC LIMIT 6""", membershipId));
        out.put("paidTotal", jdbc.queryForObject("SELECT COALESCE(sum(amount_paid), 0) FROM fee_transactions WHERE membership_id = ? AND reversal_of_transaction_id IS NULL", BigDecimal.class, membershipId));
        return out;
    }
}
