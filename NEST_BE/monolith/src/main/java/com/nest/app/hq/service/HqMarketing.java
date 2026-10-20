package com.nest.app.hq.service;

import com.nest.app.hq.HqAudit;
import com.nest.common.crypto.PiiEncryptor;
import com.nest.common.exception.BadRequestException;
import com.nest.common.exception.ResourceNotFoundException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

/**
 * Campaigns HQ runs for academies. Owleo does not place the ads itself, so delivery figures (spend,
 * reach, clicks, leads) are entered from the ad platform. What Owleo does own is the audience rule:
 * only people who agreed to marketing are counted, and under-18s are reached through a guardian.
 */
@Service
public class HqMarketing {

    private static final Set<String> CATEGORIES = Set.of("Dance", "Music", "Fine Arts", "Theatre");

    private final JdbcTemplate jdbc;
    private final HqAudit audit;
    private final PiiEncryptor encryptor;

    public HqMarketing(JdbcTemplate jdbc, HqAudit audit, PiiEncryptor encryptor) {
        this.jdbc = jdbc;
        this.audit = audit;
        this.encryptor = encryptor;
    }

    public Map<String, Object> list(String channel) {
        var rows = jdbc.queryForList("""
                SELECT c.*, a.name AS academy FROM hq_campaigns c JOIN academies a ON a.id = c.academy_id ORDER BY
                  CASE c.status WHEN 'LIVE' THEN 0 WHEN 'DRAFT' THEN 1 WHEN 'PAUSED' THEN 2 ELSE 3 END, c.created_at DESC""");
        BigDecimal spend = BigDecimal.ZERO;
        long leads = 0;
        int live = 0;
        java.util.Set<Object> academies = new java.util.HashSet<>();
        List<Map<String, Object>> items = new ArrayList<>();
        for (var r : rows) {
            spend = spend.add((BigDecimal) r.get("spend"));
            leads += ((Number) r.get("leads")).longValue();
            if ("LIVE".equals(r.get("status"))) live++;
            academies.add(r.get("academy_id"));
            String ch = (String) r.get("channel");
            if (channel != null && !channel.equals("all") && !channel.equals(ch) && !"BOTH".equals(ch)) continue;
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("id", r.get("id"));
            m.put("name", r.get("name"));
            m.put("academyId", r.get("academy_id"));
            m.put("academy", r.get("academy"));
            m.put("channel", ch);
            m.put("audience", audienceText(r));
            m.put("status", ((String) r.get("status")).toLowerCase());
            m.put("budget", r.get("budget"));
            m.put("spend", r.get("spend"));
            m.put("reach", r.get("reach"));
            m.put("clicks", r.get("clicks"));
            m.put("leads", r.get("leads"));
            m.put("endsOn", r.get("ends_on"));
            items.add(m);
        }
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("items", items);
        out.put("live", live);
        out.put("academies", academies.size());
        out.put("spend", spend);
        out.put("leads", leads);
        out.put("costPerLead", leads == 0 ? null : spend.divide(BigDecimal.valueOf(leads), 0, java.math.RoundingMode.HALF_UP));
        out.put("academyList", jdbc.queryForList("SELECT id, name FROM academies WHERE closed_at IS NULL ORDER BY name"));
        return out;
    }

    private static String audienceText(Map<String, Object> r) {
        String who = switch ((String) r.get("audience")) { case "GUARD" -> "Parents of under-18s"; case "ADULT" -> "Adult students"; default -> "Parents and adult students"; };
        String ints = (String) r.get("interests");
        return who + (ints == null || ints.isBlank() ? "" : ", " + ints.replace(",", ", "));
    }

    /** How many of the academy's own students a campaign could reach, and how many are left out for lack of consent. */
    public Map<String, Object> estimate(UUID academy, String audience, List<String> interests) {
        int total = 0, reachable = 0;
        for (var r : jdbc.queryForList("""
                SELECT u.dob, u.marketing_consent,
                       COALESCE((SELECT array_agg(DISTINCT c.category) FROM batch_members bm JOIN batches b ON b.id = bm.batch_id JOIN courses c ON c.id = b.course_id WHERE bm.membership_id = m.id), '{}') AS cats
                FROM academy_memberships m JOIN users u ON u.id = m.user_id
                WHERE m.academy_id = ? AND m.role_type = 'STUDENT' AND m.status = 'ACTIVE'""", academy)) {
            total++;
            if (!Boolean.TRUE.equals(r.get("marketing_consent"))) continue;
            Integer age = ageOf(r.get("dob"));
            boolean minor = age != null && age < 18;
            if ("GUARD".equals(audience) && !minor) continue;
            if ("ADULT".equals(audience) && minor) continue;
            if (!interests.isEmpty()) {
                List<String> cats = new ArrayList<>();
                try {
                    for (String c : (String[]) ((java.sql.Array) r.get("cats")).getArray()) cats.add(HqAcademies.typeLabel(c));
                } catch (Exception ignored) {
                    // no categories
                }
                if (cats.stream().noneMatch(interests::contains)) continue;
            }
            reachable++;
        }
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("reachable", reachable);
        out.put("total", total);
        out.put("excluded", jdbc.queryForObject("""
                SELECT count(*) FROM academy_memberships m JOIN users u ON u.id = m.user_id
                WHERE m.academy_id = ? AND m.role_type = 'STUDENT' AND m.status = 'ACTIVE' AND NOT u.marketing_consent""", Integer.class, academy));
        out.put("lookalike", reachable * 9);
        return out;
    }

    private Integer ageOf(Object dobEnc) {
        if (dobEnc == null || dobEnc.toString().isBlank()) return null;
        try {
            return (int) java.time.temporal.ChronoUnit.YEARS.between(LocalDate.parse(encryptor.decrypt(dobEnc.toString())), LocalDate.now());
        } catch (Exception e) {
            return null;
        }
    }

    @Transactional
    public UUID create(Map<String, Object> b) {
        String name = str(b, "name");
        if (name.length() < 3) throw new BadRequestException("Give the campaign a name.");
        UUID academy;
        try {
            academy = UUID.fromString(str(b, "academyId"));
        } catch (Exception e) {
            throw new BadRequestException("Choose an academy.");
        }
        if (jdbc.queryForObject("SELECT count(*) FROM academies WHERE id = ? AND closed_at IS NULL", Integer.class, academy) == 0) throw new BadRequestException("Choose an academy.");
        String channel = str(b, "channel").toUpperCase(), audience = str(b, "audience").toUpperCase();
        if (!Set.of("META", "INAPP", "BOTH").contains(channel)) throw new BadRequestException("Choose a channel.");
        if (!Set.of("GUARD", "ADULT", "ALL").contains(audience)) throw new BadRequestException("Choose who sees it.");
        BigDecimal budget;
        try {
            budget = new BigDecimal(str(b, "budget"));
        } catch (Exception e) {
            throw new BadRequestException("Enter the budget.");
        }
        if (budget.signum() <= 0) throw new BadRequestException("Enter a budget above zero.");
        int days = b.get("days") instanceof Number n ? n.intValue() : 14;
        if (days != 7 && days != 14 && days != 30) throw new BadRequestException("Choose how long it runs.");
        List<String> interests = new ArrayList<>();
        if (b.get("interests") instanceof List<?> l) {
            for (Object o : l) if (CATEGORIES.contains(String.valueOf(o))) interests.add(String.valueOf(o));
        }
        UUID id = UUID.randomUUID();
        jdbc.update("INSERT INTO hq_campaigns (id, name, academy_id, channel, audience, interests, budget, days) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                id, name, academy, channel, audience, String.join(",", interests), budget, days);
        audit.log("marketing", academy, "Created campaign " + name + " as a draft");
        return id;
    }

    private Map<String, Object> campaign(UUID id) {
        var rows = jdbc.queryForList("SELECT * FROM hq_campaigns WHERE id = ?", id);
        if (rows.isEmpty()) throw new ResourceNotFoundException("Campaign not found");
        return rows.get(0);
    }

    @Transactional
    public void setStatus(UUID id, String action) {
        var c = campaign(id);
        String st = (String) c.get("status");
        String next = switch (action) {
            case "launch" -> { if (!"DRAFT".equals(st)) throw new BadRequestException("Only a draft can be launched."); yield "LIVE"; }
            case "pause" -> { if (!"LIVE".equals(st)) throw new BadRequestException("Only a live campaign can be paused."); yield "PAUSED"; }
            case "resume" -> { if (!"PAUSED".equals(st)) throw new BadRequestException("Only a paused campaign can be resumed."); yield "LIVE"; }
            case "end" -> { if ("ENDED".equals(st)) throw new BadRequestException("Already ended."); yield "ENDED"; }
            default -> throw new BadRequestException("Unknown action.");
        };
        if ("LIVE".equals(next) && "DRAFT".equals(st)) {
            LocalDate start = LocalDate.now();
            jdbc.update("UPDATE hq_campaigns SET status = 'LIVE', starts_on = ?, ends_on = ? WHERE id = ?", start, start.plusDays(((Number) c.get("days")).longValue()), id);
        } else {
            jdbc.update("UPDATE hq_campaigns SET status = ? WHERE id = ?", next, id);
        }
        audit.log("marketing", (UUID) c.get("academy_id"), switch (action) { case "launch" -> "Launched"; case "pause" -> "Paused"; case "resume" -> "Resumed"; default -> "Ended"; } + " campaign " + c.get("name"));
    }

    /** Delivery figures from the ad platform. */
    @Transactional
    public void recordResults(UUID id, Map<String, Object> b) {
        var c = campaign(id);
        BigDecimal spend = new BigDecimal(str(b, "spend").isEmpty() ? "0" : str(b, "spend"));
        long reach = num(b, "reach"), clicks = num(b, "clicks"), leads = num(b, "leads");
        if (spend.signum() < 0 || reach < 0 || clicks < 0 || leads < 0) throw new BadRequestException("Numbers cannot be negative.");
        if (spend.compareTo((BigDecimal) c.get("budget")) > 0) throw new BadRequestException("Spend is above the budget.");
        if (clicks > reach) throw new BadRequestException("Clicks cannot be more than reach.");
        jdbc.update("UPDATE hq_campaigns SET spend = ?, reach = ?, clicks = ?, leads = ? WHERE id = ?", spend, reach, clicks, leads, id);
        audit.log("marketing", (UUID) c.get("academy_id"), "Updated delivery figures of " + c.get("name"));
    }

    private static long num(Map<String, Object> b, String k) {
        try {
            return Long.parseLong(str(b, k).isEmpty() ? "0" : str(b, k));
        } catch (NumberFormatException e) {
            throw new BadRequestException("Enter whole numbers for reach, clicks and leads.");
        }
    }

    private static String str(Map<String, Object> b, String k) {
        Object v = b.get(k);
        return v == null ? "" : v.toString().trim();
    }
}
