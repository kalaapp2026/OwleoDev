package com.nest.app.hq.service;

import com.nest.app.hq.HqAudit;
import com.nest.common.exception.BadRequestException;
import com.nest.common.exception.ConflictException;
import com.nest.common.exception.ResourceNotFoundException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

/** The plans academies subscribe to: what they cost, what they cap and which extras they include. */
@Service
public class HqPlansService {

    private static final Set<String> TONES = Set.of("blue", "gold", "violet", "green", "coral", "magenta", "primary", "mute");
    private static final Set<String> MODULES = Set.of("events", "services", "study", "branding", "priority", "manager");

    private final JdbcTemplate jdbc;
    private final HqAudit audit;

    public HqPlansService(JdbcTemplate jdbc, HqAudit audit) {
        this.jdbc = jdbc;
        this.audit = audit;
    }

    @Transactional(readOnly = true)
    public List<Map<String, Object>> list() {
        return jdbc.query("""
                SELECT p.code, p.display_name, p.monthly_price, p.max_students, p.max_trainers, p.tone, p.popular, p.modules,
                       (SELECT count(*) FROM academies a WHERE a.plan = p.code AND a.closed_at IS NULL AND a.demo_ends_on IS NULL) AS academies
                FROM billing_plans p WHERE p.active ORDER BY p.monthly_price, p.display_name""", (rs, i) -> {
            Map<String, Object> m = new LinkedHashMap<>();
            BigDecimal price = rs.getBigDecimal("monthly_price");
            long academies = rs.getLong("academies");
            m.put("code", rs.getString("code"));
            m.put("name", rs.getString("display_name"));
            m.put("price", price);
            m.put("maxStudents", rs.getObject("max_students"));
            m.put("maxTrainers", rs.getObject("max_trainers"));
            m.put("tone", rs.getString("tone"));
            m.put("popular", rs.getBoolean("popular"));
            String mods = rs.getString("modules");
            m.put("modules", mods == null || mods.isBlank() ? List.of() : Arrays.asList(mods.split(",")));
            m.put("academies", academies);
            m.put("monthly", price.multiply(BigDecimal.valueOf(academies)));
            return m;
        });
    }

    @Transactional
    public void save(String code, Map<String, Object> b) {
        String name = str(b.get("name"));
        if (name.length() < 2) throw new BadRequestException("Enter a plan name of at least 2 letters.");
        BigDecimal price = decimal(b.get("price"));
        if (price == null || price.signum() <= 0) throw new BadRequestException("Enter a monthly price above zero.");
        Integer maxStudents = limit(b.get("maxStudents"), "Student");
        Integer maxTrainers = limit(b.get("maxTrainers"), "Trainer");
        String tone = TONES.contains(str(b.get("tone"))) ? str(b.get("tone")) : "blue";
        boolean popular = Boolean.TRUE.equals(b.get("popular"));
        String modules = ((List<?>) (b.get("modules") == null ? List.of() : b.get("modules"))).stream()
                .map(Object::toString).filter(MODULES::contains).distinct().collect(java.util.stream.Collectors.joining(","));

        Integer same = jdbc.queryForObject("SELECT count(*) FROM billing_plans WHERE active AND lower(display_name) = lower(?) AND code <> ?",
                Integer.class, name, code == null ? "" : code);
        if (same != null && same > 0) throw new ConflictException("Another plan already has this name.");

        if (code == null) {
            String base = name.toUpperCase().replaceAll("[^A-Z0-9]+", "");
            String c = base.isEmpty() ? "PLAN" : base;
            while (Boolean.TRUE.equals(jdbc.queryForObject("SELECT EXISTS (SELECT 1 FROM billing_plans WHERE code = ?)", Boolean.class, c))) {
                c += "X";
            }
            jdbc.update("""
                    INSERT INTO billing_plans (code, display_name, monthly_price, max_students, max_trainers, active, tone, popular, modules)
                    VALUES (?, ?, ?, ?, ?, TRUE, ?, FALSE, ?)""", c, name, price, maxStudents, maxTrainers, tone, modules);
            if (popular) setPopular(c);
            audit.log("plans", "Added plan " + name + " at ₹" + price.toBigInteger());
        } else {
            Map<String, Object> cur = jdbc.queryForList("SELECT monthly_price FROM billing_plans WHERE code = ? AND active", code)
                    .stream().findFirst().orElseThrow(() -> new ResourceNotFoundException("Plan not found: " + code));
            if (maxStudents != null) {
                Integer over = jdbc.queryForObject("""
                        SELECT count(*) FROM academies a WHERE a.plan = ? AND a.closed_at IS NULL AND
                        (SELECT count(*) FROM academy_memberships m WHERE m.academy_id = a.id AND m.role_type = 'STUDENT' AND m.status = 'ACTIVE') > ?""",
                        Integer.class, code, maxStudents);
                if (over != null && over > 0) {
                    throw new BadRequestException(over + (over == 1 ? " academy on this plan already has" : " academies on this plan already have")
                            + " more than " + maxStudents + " students.");
                }
            }
            jdbc.update("""
                    UPDATE billing_plans SET display_name = ?, monthly_price = ?, max_students = ?, max_trainers = ?, tone = ?, modules = ?
                    WHERE code = ?""", name, price, maxStudents, maxTrainers, tone, modules, code);
            if (popular) setPopular(code);
            else jdbc.update("UPDATE billing_plans SET popular = FALSE WHERE code = ?", code);
            BigDecimal old = (BigDecimal) cur.get("monthly_price");
            audit.log("plans", "Edited plan " + name + (old.compareTo(price) != 0 ? " (price ₹" + old.toBigInteger() + " to ₹" + price.toBigInteger() + ")" : ""));
        }
    }

    private void setPopular(String code) {
        jdbc.update("UPDATE billing_plans SET popular = (code = ?)", code);
    }

    /** Removes a plan from sale and moves its academies to another. The row stays (inactive) so past
     * invoices keep the name they were raised under. */
    @Transactional
    public void delete(String code, String moveTo) {
        Map<String, Object> plan = jdbc.queryForList("SELECT display_name, popular FROM billing_plans WHERE code = ? AND active", code)
                .stream().findFirst().orElseThrow(() -> new ResourceNotFoundException("Plan not found: " + code));
        Integer others = jdbc.queryForObject("SELECT count(*) FROM billing_plans WHERE active AND code <> ?", Integer.class, code);
        if (others == null || others == 0) throw new BadRequestException("This is the only plan. Add another plan first.");
        Integer on = jdbc.queryForObject("SELECT count(*) FROM academies WHERE plan = ?", Integer.class, code);
        if (on != null && on > 0) {
            if (moveTo == null || moveTo.equals(code)) throw new BadRequestException("Choose a plan to move the academies to.");
            Map<String, Object> target = jdbc.queryForList("SELECT max_students, display_name FROM billing_plans WHERE code = ? AND active", moveTo)
                    .stream().findFirst().orElseThrow(() -> new BadRequestException("Unknown plan: " + moveTo));
            Integer max = (Integer) target.get("max_students");
            if (max != null) {
                Integer over = jdbc.queryForObject("""
                        SELECT count(*) FROM academies a WHERE a.plan = ? AND
                        (SELECT count(*) FROM academy_memberships m WHERE m.academy_id = a.id AND m.role_type = 'STUDENT' AND m.status = 'ACTIVE') > ?""",
                        Integer.class, code, max);
                if (over != null && over > 0) throw new BadRequestException(over + " academies have more students than the " + target.get("display_name") + " limit. Pick a bigger plan.");
            }
            jdbc.update("UPDATE academies SET plan = ? WHERE plan = ?", moveTo, code);
            if (Boolean.TRUE.equals(plan.get("popular"))) jdbc.update("UPDATE billing_plans SET popular = TRUE WHERE code = ?", moveTo);
        }
        jdbc.update("UPDATE hq_offers SET applies_to = 'all' WHERE applies_to = ?", code);
        jdbc.update("UPDATE billing_plans SET active = FALSE, popular = FALSE WHERE code = ?", code);
        audit.log("plans", "Deleted plan " + plan.get("display_name") + (on != null && on > 0 ? " and moved " + on + " academies" : ""));
    }

    private static String str(Object o) {
        return o == null ? "" : o.toString().trim();
    }

    private static BigDecimal decimal(Object o) {
        try {
            return o == null ? null : new BigDecimal(o.toString().replace(",", ""));
        } catch (NumberFormatException e) {
            return null;
        }
    }

    /** Blank or absent means unlimited (stored as NULL). */
    private static Integer limit(Object o, String what) {
        String s = str(o);
        if (s.isEmpty()) return null;
        if (!s.matches("\\d+") || Integer.parseInt(s) <= 0) {
            throw new BadRequestException(what + " limit must be a whole number, or leave blank for unlimited.");
        }
        return Integer.parseInt(s);
    }
}
