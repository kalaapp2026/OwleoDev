package com.nest.app.hq.service;

import com.nest.app.hq.HqAudit;
import com.nest.common.exception.BadRequestException;
import com.nest.common.exception.ResourceNotFoundException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.DayOfWeek;
import java.time.LocalDate;
import java.time.LocalTime;
import java.time.format.TextStyle;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.UUID;

/**
 * The batches running across every academy, and the three things worth chasing: a batch with no
 * trainer, a batch with no schedule, and a batch that is still active long after its end date.
 *
 * <p>Status is derived: INACTIVE is Ended; an ACTIVE batch that has not started is Upcoming; the
 * rest are Running. "Outdated" is a Running batch whose end date has passed, which usually means
 * nobody closed it.
 */
@Service
public class HqCourses {

    private final JdbcTemplate jdbc;
    private final HqAudit audit;

    public HqCourses(JdbcTemplate jdbc, HqAudit audit) {
        this.jdbc = jdbc;
        this.audit = audit;
    }

    private static final String BASE = """
            SELECT b.id, b.name AS batch, b.status AS raw_status, b.start_date, b.end_date, c.id AS course_id, c.name AS course,
                   a.id AS academy_id, a.name AS academy,
                   (SELECT count(*) FROM batch_members bm JOIN academy_memberships m ON m.id = bm.membership_id WHERE bm.batch_id = b.id AND m.status = 'ACTIVE') AS enrolled,
                   (SELECT string_agg(tu.full_name, ', ' ORDER BY tu.full_name) FROM batch_trainers bt
                      JOIN academy_memberships tm ON tm.id = bt.trainer_membership_id JOIN users tu ON tu.id = tm.user_id WHERE bt.batch_id = b.id) AS trainers,
                   (SELECT string_agg(s.day_of_week || '|' || s.start_time, ',' ORDER BY s.day_of_week) FROM schedules s WHERE s.batch_id = b.id) AS slots
            FROM batches b JOIN courses c ON c.id = b.course_id JOIN academies a ON a.id = c.academy_id
            WHERE a.closed_at IS NULL""";

    public Map<String, Object> list(UUID academy, String status, String issue, String q) {
        LocalDate today = LocalDate.now();
        List<Map<String, Object>> all = new ArrayList<>();
        int running = 0, enrolled = 0, noTrainer = 0, incomplete = 0, outdated = 0;
        for (var r : jdbc.queryForList(BASE + " ORDER BY a.name, c.name, b.name")) {
            LocalDate start = date(r.get("start_date")), end = date(r.get("end_date"));
            String st = !"ACTIVE".equals(r.get("raw_status")) ? "Ended" : start != null && start.isAfter(today) ? "Upcoming" : "Running";
            boolean live = !"Ended".equals(st);
            List<String> flags = new ArrayList<>();
            if (live && r.get("trainers") == null) flags.add("No trainer");
            if (live && r.get("slots") == null) flags.add("Incomplete");
            if ("Running".equals(st) && end != null && end.isBefore(today)) flags.add("Outdated");

            Map<String, Object> m = new LinkedHashMap<>();
            m.put("id", r.get("id"));
            m.put("academyId", r.get("academy_id"));
            m.put("academy", r.get("academy"));
            m.put("course", r.get("course"));
            m.put("batch", r.get("batch"));
            m.put("trainer", r.get("trainers"));
            m.put("enrolled", r.get("enrolled"));
            m.put("start", start);
            m.put("end", end);
            m.put("schedule", schedule((String) r.get("slots")));
            m.put("status", st);
            m.put("flags", flags);

            // Platform totals ignore the filters, as the console's KPI cards do.
            if ("Running".equals(st)) running++;
            if ("Running".equals(st)) enrolled += ((Number) r.get("enrolled")).intValue();
            if (flags.contains("No trainer")) noTrainer++;
            if (flags.contains("Incomplete")) incomplete++;
            if (flags.contains("Outdated")) outdated++;
            all.add(m);
        }
        String needle = q == null ? "" : q.trim().toLowerCase();
        List<Map<String, Object>> shown = all.stream()
                .filter(m -> academy == null || academy.equals(m.get("academyId")))
                .filter(m -> status == null || status.isBlank() || "all".equals(status) || status.equals(m.get("status")))
                .filter(m -> issue == null || issue.isBlank() || "all".equals(issue) || ((List<?>) m.get("flags")).contains(issue))
                .filter(m -> needle.isEmpty() || (m.get("course") + " " + m.get("batch")).toLowerCase().contains(needle))
                .toList();
        final int fNoTrainer = noTrainer, fIncomplete = incomplete, fOutdated = outdated;
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("total", all.size());
        out.put("running", running);
        out.put("enrolled", enrolled);
        out.put("noTrainer", fNoTrainer);
        out.put("incomplete", fIncomplete);
        out.put("outdated", fOutdated);
        out.put("academies", jdbc.queryForList("SELECT DISTINCT a.id, a.name FROM academies a JOIN courses c ON c.academy_id = a.id JOIN batches b ON b.course_id = c.id WHERE a.closed_at IS NULL ORDER BY a.name"));
        out.put("items", shown.size() > 400 ? shown.subList(0, 400) : shown);
        out.put("shown", shown.size());
        return out;
    }

    private static LocalDate date(Object o) {
        return o == null ? null : ((java.sql.Date) o).toLocalDate();
    }

    /** "Mon, Wed · 5 pm" from "MONDAY|17:00:00,WEDNESDAY|17:00:00". */
    private static String schedule(String slots) {
        if (slots == null) return "";
        List<String> days = new ArrayList<>();
        LocalTime time = null;
        for (String part : slots.split(",")) {
            String[] p = part.split("\\|");
            days.add(DayOfWeek.valueOf(p[0]).getDisplayName(TextStyle.SHORT, Locale.ENGLISH));
            time = LocalTime.parse(p[1]);
        }
        String t = time.getMinute() == 0 ? (time.getHour() % 12 == 0 ? 12 : time.getHour() % 12) + (time.getHour() < 12 ? " am" : " pm")
                : (time.getHour() % 12 == 0 ? 12 : time.getHour() % 12) + ":" + String.format("%02d", time.getMinute()) + (time.getHour() < 12 ? " am" : " pm");
        return String.join(", ", days) + " · " + t;
    }

    private Map<String, Object> batch(UUID id) {
        var rows = jdbc.queryForList("""
                SELECT b.id, b.name, b.start_date, b.end_date, c.id AS course_id, c.name AS course, a.id AS academy_id, a.name AS academy
                FROM batches b JOIN courses c ON c.id = b.course_id JOIN academies a ON a.id = c.academy_id WHERE b.id = ?""", id);
        if (rows.isEmpty()) throw new ResourceNotFoundException("Batch not found");
        return rows.get(0);
    }

    public List<Map<String, Object>> trainerOptions(UUID batchId) {
        var b = batch(batchId);
        return jdbc.queryForList("""
                SELECT m.id, u.full_name AS name FROM academy_memberships m JOIN users u ON u.id = m.user_id
                WHERE m.academy_id = ? AND m.role_type = 'TRAINER' AND m.status = 'ACTIVE' ORDER BY u.full_name""", b.get("academy_id"));
    }

    @Transactional
    public void assignTrainer(UUID batchId, UUID membershipId) {
        var b = batch(batchId);
        var m = jdbc.queryForList("""
                SELECT u.full_name FROM academy_memberships m JOIN users u ON u.id = m.user_id
                WHERE m.id = ? AND m.academy_id = ? AND m.role_type = 'TRAINER' AND m.status = 'ACTIVE'""", membershipId, b.get("academy_id"));
        if (m.isEmpty()) throw new BadRequestException("Choose a trainer from this academy.");
        jdbc.update("INSERT INTO batch_trainers (batch_id, trainer_membership_id) VALUES (?, ?) ON CONFLICT DO NOTHING", batchId, membershipId);
        jdbc.update("""
                INSERT INTO trainer_course_batches (membership_id, course_id, batch_id) VALUES (?, ?, ?) ON CONFLICT DO NOTHING""", membershipId, b.get("course_id"), batchId);
        audit.log("courses", (UUID) b.get("academy_id"), "Assigned " + m.get(0).get("full_name") + " to " + b.get("course") + " " + b.get("name"));
    }

    @Transactional
    public void setSchedule(UUID batchId, List<String> days, String start, String end) {
        var b = batch(batchId);
        if (days == null || days.isEmpty()) throw new BadRequestException("Pick at least one day.");
        LocalTime from, to;
        try {
            from = LocalTime.parse(start);
            to = LocalTime.parse(end);
        } catch (Exception e) {
            throw new BadRequestException("Enter the start and end time.");
        }
        if (!to.isAfter(from)) throw new BadRequestException("The class must end after it starts.");
        LocalDate effective = date(b.get("start_date")) == null ? LocalDate.now() : date(b.get("start_date"));
        for (String d : days) {
            DayOfWeek dow;
            try {
                dow = DayOfWeek.valueOf(d);
            } catch (Exception e) {
                throw new BadRequestException("Unknown day: " + d);
            }
            jdbc.update("INSERT INTO schedules (id, batch_id, day_of_week, start_time, end_time, effective_from) VALUES (?, ?, ?, ?, ?, ?)",
                    UUID.randomUUID(), batchId, dow.name(), java.sql.Time.valueOf(from), java.sql.Time.valueOf(to), effective);
        }
        audit.log("courses", (UUID) b.get("academy_id"), "Set the schedule of " + b.get("course") + " " + b.get("name"));
    }

    @Transactional
    public void end(UUID batchId) {
        var b = batch(batchId);
        LocalDate end = date(b.get("end_date"));
        jdbc.update("UPDATE batches SET status = 'INACTIVE', end_date = ? WHERE id = ?",
                end == null || end.isAfter(LocalDate.now()) ? LocalDate.now() : end, batchId);
        audit.log("courses", (UUID) b.get("academy_id"), "Marked " + b.get("course") + " " + b.get("name") + " as ended");
    }
}
