package com.nest.app.hq.service;

import com.nest.app.hq.HqAudit;
import com.nest.common.exception.BadRequestException;
import com.nest.common.exception.ResourceNotFoundException;
import com.nest.common.security.TenantContext;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.sql.Timestamp;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

/**
 * Every event across academies, and what HQ may do about one: pause it (hide it from the feed
 * until resumed) or cancel it, always with a reason.
 *
 * <p>Events are published by academies, and "interested" is the only audience signal the product
 * records today. There is no ticketing, so there are no sales or commission here yet.
 */
@Service
public class HqEvents {

    private final JdbcTemplate jdbc;
    private final HqAudit audit;

    public HqEvents(JdbcTemplate jdbc, HqAudit audit) {
        this.jdbc = jdbc;
        this.audit = audit;
    }

    private static final String BASE = """
            SELECT e.id, e.title, e.type, e.description, e.event_date, e.end_date, e.location, e.venue_maps_url, e.visibility, e.status,
                   e.audience_type, e.interest_deadline, e.academy_id, a.name AS academy, a.city AS academy_city,
                   (SELECT count(*) FROM interests i WHERE i.event_id = e.id) AS interested,
                   EXISTS (SELECT 1 FROM hq_event_log l WHERE l.event_id = e.id AND l.kind = 'HOLD'
                           AND l.at = (SELECT max(l2.at) FROM hq_event_log l2 WHERE l2.event_id = e.id)) AS on_hold
            FROM events e JOIN academies a ON a.id = e.academy_id""";

    /** Derived state: Cancelled, Paused (an HQ hold on a draft), Completed, Today, Scheduled; a plain draft is Draft. */
    private static String state(Map<String, Object> r, LocalDate today) {
        String st = (String) r.get("status");
        LocalDate d = ((Timestamp) r.get("event_date")).toLocalDateTime().toLocalDate();
        if ("CANCELLED".equals(st)) return "Cancelled";
        if ("DRAFT".equals(st)) return Boolean.TRUE.equals(r.get("on_hold")) ? "Paused" : "Draft";
        if (d.isBefore(today)) return "Completed";
        return d.equals(today) ? "Today" : "Scheduled";
    }

    public Map<String, Object> list(String when, String day, String q) {
        LocalDate today = LocalDate.now(), weekEnd = today.plusDays(7);
        LocalDate onDay = day == null || day.isBlank() ? null : LocalDate.parse(day);
        var rows = jdbc.queryForList(BASE + " ORDER BY e.event_date");
        int todayN = 0, week = 0, upcoming = 0, interested = 0, attention = 0;
        List<Map<String, Object>> items = new ArrayList<>();
        Map<String, Integer> perDay = new LinkedHashMap<>();
        String needle = q == null ? "" : q.trim().toLowerCase();
        for (var r : rows) {
            LocalDate d = ((Timestamp) r.get("event_date")).toLocalDateTime().toLocalDate();
            String st = state(r, today);
            boolean live = "Today".equals(st) || "Scheduled".equals(st);
            if (live && d.equals(today)) todayN++;
            if (live && !d.isBefore(today) && !d.isAfter(weekEnd)) week++;
            if (live && !d.isBefore(today)) {
                upcoming++;
                interested += ((Number) r.get("interested")).intValue();
            }
            if (!d.isBefore(today) && ("Paused".equals(st))) attention++;
            if (!d.isBefore(today) && !d.isAfter(today.plusDays(13)) && !"Cancelled".equals(st)) perDay.merge(d.toString(), 1, Integer::sum);

            boolean inWhen = switch (when == null ? "upcoming" : when) {
                case "today" -> d.equals(today);
                case "upcoming" -> !d.isBefore(today);
                case "past" -> d.isBefore(today);
                default -> true;
            };
            if (!inWhen || (onDay != null && !d.equals(onDay))) continue;
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("id", r.get("id"));
            m.put("title", r.get("title"));
            m.put("type", r.get("type"));
            m.put("date", d);
            m.put("time", ((Timestamp) r.get("event_date")).toLocalDateTime().toLocalTime().toString().substring(0, 5));
            m.put("academyId", r.get("academy_id"));
            m.put("academy", r.get("academy"));
            m.put("venue", r.get("location"));
            m.put("state", st);
            m.put("public", "PUBLIC".equals(r.get("visibility")));
            m.put("interested", r.get("interested"));
            if (!needle.isEmpty() && !(m.get("title") + " " + m.get("academy") + " " + nz(m.get("venue")) + " " + m.get("type")).toLowerCase().contains(needle)) continue;
            items.add(m);
        }
        if ("past".equals(when)) java.util.Collections.reverse(items);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("items", items);
        out.put("today", todayN);
        out.put("week", week);
        out.put("upcoming", upcoming);
        out.put("interested", interested);
        out.put("attention", attention);
        out.put("days", perDay);
        return out;
    }

    public Map<String, Object> detail(UUID id) {
        var rows = jdbc.queryForList(BASE + " WHERE e.id = ?", id);
        if (rows.isEmpty()) throw new ResourceNotFoundException("Event not found");
        var r = rows.get(0);
        LocalDate today = LocalDate.now();
        Map<String, Object> m = new LinkedHashMap<>();
        var start = ((Timestamp) r.get("event_date")).toLocalDateTime();
        var end = r.get("end_date") == null ? null : ((Timestamp) r.get("end_date")).toLocalDateTime();
        m.put("id", id);
        m.put("title", r.get("title"));
        m.put("type", r.get("type"));
        m.put("description", r.get("description"));
        m.put("state", state(r, today));
        m.put("start", start);
        m.put("end", end);
        m.put("academyId", r.get("academy_id"));
        m.put("academy", r.get("academy"));
        m.put("venue", r.get("location"));
        String maps = (String) r.get("venue_maps_url");
        m.put("mapsUrl", maps != null && !maps.isBlank() ? maps
                : r.get("location") == null ? null : "https://www.google.com/maps/search/?api=1&query=" + URLEncoder.encode(r.get("location") + ", " + r.get("academy_city"), StandardCharsets.UTF_8));
        m.put("public", "PUBLIC".equals(r.get("visibility")));
        m.put("audience", r.get("audience_type"));
        m.put("interested", r.get("interested"));
        m.put("interestDeadline", r.get("interest_deadline"));
        m.put("log", jdbc.queryForList("SELECT text AS x, actor_name AS who, at FROM hq_event_log WHERE event_id = ? ORDER BY at DESC", id));
        return m;
    }

    private Map<String, Object> event(UUID id) {
        var rows = jdbc.queryForList("SELECT e.id, e.title, e.status, e.event_date, e.academy_id FROM events e WHERE e.id = ?", id);
        if (rows.isEmpty()) throw new ResourceNotFoundException("Event not found");
        return rows.get(0);
    }

    private String actor() {
        UUID a = TenantContext.currentUserIdOrNull();
        var n = a == null ? List.<String>of() : jdbc.queryForList("SELECT full_name FROM users WHERE id = ?", String.class, a);
        return n.isEmpty() ? "Owleo staff" : n.get(0);
    }

    private static String nz(Object o) {
        return o == null ? "" : o.toString();
    }

    private void requireUpcoming(Map<String, Object> e) {
        if (((Timestamp) e.get("event_date")).toLocalDateTime().toLocalDate().isBefore(LocalDate.now())) throw new BadRequestException("This event has already happened.");
    }

    @Transactional
    public void pause(UUID id, String reason) {
        var e = event(id);
        requireUpcoming(e);
        if (!"PUBLISHED".equals(e.get("status"))) throw new BadRequestException("Only a published event can be paused.");
        if (reason == null || reason.trim().length() < 3) throw new BadRequestException("Say why.");
        jdbc.update("UPDATE events SET status = 'DRAFT' WHERE id = ?", id);
        jdbc.update("INSERT INTO hq_event_log (event_id, kind, actor_name, text) VALUES (?, 'HOLD', ?, ?)", id, actor(), "Paused: " + reason.trim());
        audit.log("events", (UUID) e.get("academy_id"), "Paused event " + e.get("title") + ": " + reason.trim());
    }

    @Transactional
    public void resume(UUID id) {
        var e = event(id);
        var held = jdbc.queryForObject("""
                SELECT count(*) FROM hq_event_log l WHERE l.event_id = ? AND l.kind = 'HOLD'
                  AND l.at = (SELECT max(l2.at) FROM hq_event_log l2 WHERE l2.event_id = ?)""", Integer.class, id, id);
        if (!"DRAFT".equals(e.get("status")) || held == null || held == 0) throw new BadRequestException("This event is not paused by HQ.");
        jdbc.update("UPDATE events SET status = 'PUBLISHED' WHERE id = ?", id);
        jdbc.update("INSERT INTO hq_event_log (event_id, kind, actor_name, text) VALUES (?, 'RESUME', ?, 'Resumed.')", id, actor());
        audit.log("events", (UUID) e.get("academy_id"), "Resumed event " + e.get("title"));
    }

    @Transactional
    public void cancel(UUID id, String reason) {
        var e = event(id);
        requireUpcoming(e);
        if ("CANCELLED".equals(e.get("status"))) throw new BadRequestException("This event is already cancelled.");
        if (reason == null || reason.trim().length() < 3) throw new BadRequestException("Say why.");
        jdbc.update("UPDATE events SET status = 'CANCELLED' WHERE id = ?", id);
        jdbc.update("INSERT INTO hq_event_log (event_id, kind, actor_name, text) VALUES (?, 'CANCEL', ?, ?)", id, actor(), "Cancelled: " + reason.trim());
        audit.log("events", (UUID) e.get("academy_id"), "Cancelled event " + e.get("title") + ": " + reason.trim());
    }
}
