package com.nest.app.hq.service;

import com.nest.app.hq.HqAudit;
import com.nest.common.exception.BadRequestException;
import com.nest.common.exception.ConflictException;
import com.nest.common.exception.ResourceNotFoundException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.YearMonth;
import java.util.List;
import java.util.Map;
import java.util.UUID;

/** What HQ can sell and give away: promotional offers and paid add-ons, plus the reminder rules. */
@Service
public class HqCatalog {

    private final JdbcTemplate jdbc;
    private final HqAudit audit;

    public HqCatalog(JdbcTemplate jdbc, HqAudit audit) {
        this.jdbc = jdbc;
        this.audit = audit;
    }

    // ---- offers ----

    @Transactional(readOnly = true)
    public List<Map<String, Object>> offers() {
        return jdbc.queryForList("""
                SELECT o.id, o.name, o.code, lower(o.type) AS type, o.value, o.applies_to AS "appliesTo",
                       o.starts_on AS "startsOn", o.ends_on AS "endsOn", o.use_limit AS "limit", o.active,
                       (SELECT count(*) FROM academy_invoices i WHERE i.offer_id = o.id) AS used,
                       (SELECT COALESCE(SUM(i.discount), 0) FROM academy_invoices i WHERE i.offer_id = o.id) AS given
                FROM hq_offers o ORDER BY o.active DESC, o.ends_on DESC, o.code""");
    }

    @Transactional
    public void saveOffer(UUID id, Map<String, Object> b) {
        String name = str(b, "name"), code = str(b, "code").toUpperCase(), type = str(b, "type").toUpperCase(), applies = str(b, "appliesTo");
        if (name.length() < 3) throw new BadRequestException("Give the offer a name.");
        if (!code.matches("^[A-Z0-9]{4,14}$")) throw new BadRequestException("The code needs 4 to 14 letters or numbers.");
        if (!List.of("PCT", "FLAT", "FREE").contains(type)) throw new BadRequestException("Choose a discount type.");
        BigDecimal value = type.equals("FREE") ? BigDecimal.ONE : number(b.get("value"));
        if (type.equals("PCT") && (value == null || value.compareTo(BigDecimal.ONE) < 0 || value.compareTo(BigDecimal.valueOf(100)) > 0)) {
            throw new BadRequestException("Percent must be between 1 and 100.");
        }
        if (type.equals("FLAT") && (value == null || value.signum() <= 0)) throw new BadRequestException("Enter the amount off.");
        LocalDate from = date(b.get("startsOn")), to = date(b.get("endsOn"));
        if (from == null || to == null || to.isBefore(from)) throw new BadRequestException("The end date must be after the start date.");
        Integer limit = null;
        if (!str(b, "limit").isEmpty()) {
            if (!str(b, "limit").matches("\\d+") || Integer.parseInt(str(b, "limit")) <= 0) throw new BadRequestException("Use limit must be a whole number.");
            limit = Integer.parseInt(str(b, "limit"));
        }
        if (applies.isEmpty()) applies = "all";
        if (!applies.equals("all") && jdbc.queryForObject("SELECT count(*) FROM billing_plans WHERE code = ?", Integer.class, applies) == 0) {
            throw new BadRequestException("Unknown plan: " + applies);
        }
        Integer clash = jdbc.queryForObject("SELECT count(*) FROM hq_offers WHERE code = ? AND (? IS NULL OR id <> ?)", Integer.class, code, id, id);
        if (clash != null && clash > 0) throw new ConflictException("Another offer already uses that code.");
        if (id == null) {
            jdbc.update("""
                    INSERT INTO hq_offers (name, code, type, value, applies_to, starts_on, ends_on, use_limit) VALUES (?, ?, ?, ?, ?, ?, ?, ?)""",
                    name, code, type, value, applies, from, to, limit);
        } else {
            int n = jdbc.update("""
                    UPDATE hq_offers SET name = ?, code = ?, type = ?, value = ?, applies_to = ?, starts_on = ?, ends_on = ?, use_limit = ? WHERE id = ?""",
                    name, code, type, value, applies, from, to, limit, id);
            if (n == 0) throw new ResourceNotFoundException("Offer not found.");
        }
        audit.log("collections", (id == null ? "Created" : "Edited") + " offer " + code);
    }

    @Transactional
    public void setOfferActive(UUID id, boolean active) {
        int n = jdbc.update("UPDATE hq_offers SET active = ? WHERE id = ?", active, id);
        if (n == 0) throw new ResourceNotFoundException("Offer not found.");
        audit.log("collections", (active ? "Resumed" : "Paused") + " an offer");
    }

    // ---- add-ons ----

    @Transactional(readOnly = true)
    public List<Map<String, Object>> addons() {
        return jdbc.queryForList("""
                SELECT d.id, d.name, d.description, d.price, lower(d.billing) AS billing, d.on_sale AS "onSale",
                       (SELECT count(*) FROM academy_addons x WHERE x.addon_id = d.id) AS academies
                FROM hq_addons d ORDER BY d.on_sale DESC, d.name""");
    }

    @Transactional
    public void saveAddon(UUID id, Map<String, Object> b) {
        String name = str(b, "name"), desc = str(b, "description"), billing = str(b, "billing").toUpperCase();
        BigDecimal price = number(b.get("price"));
        if (name.length() < 3) throw new BadRequestException("Give it a name.");
        if (desc.length() < 5) throw new BadRequestException("Say what the academy gets.");
        if (price == null || price.signum() <= 0) throw new BadRequestException("Enter the price.");
        if (!List.of("MONTH", "ONE_TIME").contains(billing)) throw new BadRequestException("Choose how it is billed.");
        if (id == null) {
            jdbc.update("INSERT INTO hq_addons (name, description, price, billing) VALUES (?, ?, ?, ?)", name, desc, price, billing);
        } else {
            int n = jdbc.update("UPDATE hq_addons SET name = ?, description = ?, price = ?, billing = ? WHERE id = ?", name, desc, price, billing, id);
            if (n == 0) throw new ResourceNotFoundException("Add-on not found.");
        }
        audit.log("collections", (id == null ? "Created" : "Edited") + " add-on " + name);
    }

    @Transactional
    public void setAddonOnSale(UUID id, boolean onSale) {
        int n = jdbc.update("UPDATE hq_addons SET on_sale = ? WHERE id = ?", onSale, id);
        if (n == 0) throw new ResourceNotFoundException("Add-on not found.");
        audit.log("collections", (onSale ? "Put an add-on on sale" : "Took an add-on off sale"));
    }

    /** Adds an add-on to an academy from its next bill. */
    @Transactional
    public void assignAddon(UUID academyId, UUID addonId) {
        var addon = jdbc.queryForList("SELECT name, on_sale FROM hq_addons WHERE id = ?", addonId).stream().findFirst()
                .orElseThrow(() -> new ResourceNotFoundException("Add-on not found."));
        if (!(Boolean) addon.get("on_sale")) throw new BadRequestException("That add-on is off sale.");
        Integer dup = jdbc.queryForObject("SELECT count(*) FROM academy_addons WHERE academy_id = ? AND addon_id = ?", Integer.class, academyId, addonId);
        if (dup != null && dup > 0) throw new ConflictException("This academy already has that add-on.");
        String from = YearMonth.now().plusMonths(1).toString();
        jdbc.update("INSERT INTO academy_addons (academy_id, addon_id, from_period) VALUES (?, ?, ?)", academyId, addonId, from);
        audit.log("collections", academyId, "Added add-on " + addon.get("name"));
    }

    @Transactional
    public void removeAddon(UUID academyId, UUID addonId) {
        jdbc.update("DELETE FROM academy_addons WHERE academy_id = ? AND addon_id = ?", academyId, addonId);
        audit.log("collections", academyId, "Removed an add-on");
    }

    // ---- reminder rules ----

    @Transactional
    public void saveReminderSettings(Map<String, Object> b) {
        jdbc.update("""
                UPDATE hq_reminder_settings SET before_3d = ?, on_due = ?, after_3d = ?, weekly = ?, ch_whatsapp = ?, ch_email = ?, ch_sms = ? WHERE id = 1""",
                flag(b, "b3"), flag(b, "d0"), flag(b, "a3"), flag(b, "wk"), flag(b, "wa"), flag(b, "em"), flag(b, "sm"));
        audit.log("collections", "Changed the automatic reminder rules");
    }

    private static boolean flag(Map<String, Object> b, String k) {
        return Boolean.TRUE.equals(b.get(k));
    }

    private static String str(Map<String, Object> b, String k) {
        Object v = b.get(k);
        return v == null ? "" : v.toString().trim();
    }

    private static BigDecimal number(Object o) {
        try {
            return o == null || o.toString().isBlank() ? null : new BigDecimal(o.toString().replace(",", ""));
        } catch (NumberFormatException e) {
            return null;
        }
    }

    private static LocalDate date(Object o) {
        try {
            return o == null ? null : LocalDate.parse(o.toString().substring(0, 10));
        } catch (Exception e) {
            return null;
        }
    }
}
