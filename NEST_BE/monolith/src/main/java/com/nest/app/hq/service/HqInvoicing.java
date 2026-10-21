package com.nest.app.hq.service;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.nest.app.hq.HqAudit;
import com.nest.app.hq.service.HqBilling.Line;
import com.nest.app.notification.entity.NotificationModule;
import com.nest.app.notification.entity.NotificationType;
import com.nest.app.notification.service.NotificationService;
import com.nest.common.exception.BadRequestException;
import com.nest.common.exception.ResourceNotFoundException;
import com.nest.common.security.TenantContext;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.sql.Timestamp;
import java.time.LocalDate;
import java.time.YearMonth;
import java.time.format.DateTimeFormatter;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

/**
 * The monthly bill run to academy admins: when bills are made and sent, what each academy's next bill will
 * hold (its plan and add-ons, anything the owner changed, a discount or offer, or "skip this month"), the run
 * itself, and sending. Bills are real academy_invoices rows, so everything made here shows up in Collections.
 * Sending reaches the academy's admins in the Owleo Nest app and by email, on the channels that are set up;
 * a channel that is not set up is reported as skipped, never faked.
 */
@Service
public class HqInvoicing {

    private static final Logger log = LoggerFactory.getLogger(HqInvoicing.class);
    private static final Set<String> LINE_KINDS = Set.of("PLAN", "ADDON", "SETUP", "CUSTOM");
    private static final DateTimeFormatter MONTH = DateTimeFormatter.ofPattern("MMMM yyyy", Locale.ENGLISH);
    private static final DateTimeFormatter DAY = DateTimeFormatter.ofPattern("d MMM", Locale.ENGLISH);

    private final JdbcTemplate jdbc;
    private final HqAudit audit;
    private final HqBilling billing;
    private final HqChannels channels;
    private final HqNotifications templates;
    private final NotificationService notifications;
    private final ObjectMapper json;

    public HqInvoicing(JdbcTemplate jdbc, HqAudit audit, HqBilling billing, HqChannels channels, HqNotifications templates,
                       NotificationService notifications, ObjectMapper json) {
        this.jdbc = jdbc;
        this.audit = audit;
        this.billing = billing;
        this.channels = channels;
        this.templates = templates;
        this.notifications = notifications;
        this.json = json;
    }

    // ---- settings and dates ----

    public record Settings(boolean auto, int gen, String sm, int after, int sday, int due, boolean mail, boolean app, boolean wa) {

        public LocalDate genDate(String period) {
            return YearMonth.parse(period).atDay(gen);
        }

        public LocalDate sendDate(String period) {
            LocalDate g = genDate(period);
            return switch (sm) {
                case "after" -> g.plusDays(after);
                case "day" -> YearMonth.parse(period).atDay(sday);
                default -> g;
            };
        }

        public LocalDate dueDate(String period) {
            return sendDate(period).plusDays(due);
        }
    }

    public Settings settings() {
        var r = jdbc.queryForMap("SELECT * FROM hq_invoice_settings WHERE id = 1");
        return new Settings((Boolean) r.get("auto"), ((Number) r.get("gen_day")).intValue(), (String) r.get("send_mode"), ((Number) r.get("send_after")).intValue(),
                ((Number) r.get("send_day")).intValue(), ((Number) r.get("due_days")).intValue(), (Boolean) r.get("ch_mail"), (Boolean) r.get("ch_app"), (Boolean) r.get("ch_wa"));
    }

    private Map<String, Object> settingsJson(Settings s, String period) {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("auto", s.auto());
        m.put("gen", s.gen());
        m.put("sm", s.sm());
        m.put("after", s.after());
        m.put("sday", s.sday());
        m.put("due", s.due());
        m.put("ch", Map.of("em", s.mail(), "app", s.app(), "wa", s.wa()));
        // Which of the picked channels can actually deliver today.
        Map<String, Boolean> ready = channels.ready();
        m.put("ready", Map.of("em", ready.get("mail"), "app", true, "wa", ready.get("wa")));
        m.put("period", period);
        m.put("monthLabel", label(period));
        m.put("dates", Map.of("generate", s.genDate(period).toString(), "send", s.sendDate(period).toString(), "due", s.dueDate(period).toString()));
        m.put("daysToGenerate", ChronoUnit.DAYS.between(LocalDate.now(), s.genDate(period)));
        return m;
    }

    @Transactional
    public void saveSettings(Map<String, Object> b) {
        int gen = intOf(b.get("gen"), 1), after = intOf(b.get("after"), 2), sday = intOf(b.get("sday"), 5), due = intOf(b.get("due"), 14);
        String sm = str(b.get("sm"));
        if (!Set.of("same", "after", "day").contains(sm)) throw new BadRequestException("Choose when the bills are sent.");
        if (gen < 1 || gen > 28) throw new BadRequestException("Bills are generated on a day from 1 to 28.");
        if (after < 1 || after > 28 || sday < 1 || sday > 28) throw new BadRequestException("Choose a day from 1 to 28.");
        if (due < 1 || due > 60) throw new BadRequestException("Payment is due 1 to 60 days after sending.");
        if (sm.equals("day") && sday < gen) throw new BadRequestException("The send day must be on or after the day bills are generated.");
        @SuppressWarnings("unchecked") Map<String, Object> ch = b.get("ch") instanceof Map<?, ?> m ? (Map<String, Object>) m : Map.of();
        boolean mail = Boolean.TRUE.equals(ch.get("em")), app = Boolean.TRUE.equals(ch.get("app")), wa = Boolean.TRUE.equals(ch.get("wa"));
        if (!(mail || app || wa)) throw new BadRequestException("Pick at least one way to send.");
        jdbc.update("""
                UPDATE hq_invoice_settings SET auto = ?, gen_day = ?, send_mode = ?, send_after = ?, send_day = ?, due_days = ?, ch_mail = ?, ch_app = ?, ch_wa = ? WHERE id = 1""",
                Boolean.TRUE.equals(b.get("auto")), gen, sm, after, sday, due, mail, app, wa);
        audit.log("invoicing", "Changed the bill schedule: generate on day " + gen + (Boolean.TRUE.equals(b.get("auto")) ? ", automatic" : ", by hand"));
    }

    // ---- the next run ----

    /** The month the next run is for: the current one, unless it is done (a run exists, or every academy already has its bill). */
    public String nextPeriod() {
        YearMonth p = YearMonth.now();
        for (int i = 0; i < 24; i++) {
            boolean done = !jdbc.queryForList("SELECT 1 FROM hq_invoice_runs WHERE period = ?", p.toString()).isEmpty()
                    || billing.billable(p.toString(), null).isEmpty();
            if (!done) break;
            p = p.plusMonths(1);
        }
        return p.toString();
    }

    @Transactional
    public Map<String, Object> next() {
        String period = nextPeriod();
        Settings s = settings();
        Map<String, Object> out = new LinkedHashMap<>(settingsJson(s, period));
        BigDecimal gst = billing.gstRate();
        List<Map<String, Object>> list = new ArrayList<>();
        for (var a : billing.billable(period, null)) {
            list.add(academyDraft(a, period, gst));
        }
        out.put("gst", gst);
        out.put("academies", list);
        out.put("offers", activeOffers());
        out.put("template", templateInfo());
        return out;
    }

    private Map<String, Object> academyDraft(Map<String, Object> a, String period, BigDecimal gst) {
        UUID id = (UUID) a.get("id");
        var rows = jdbc.queryForList("SELECT * FROM hq_invoice_drafts WHERE academy_id = ?", id);
        var d = rows.isEmpty() ? null : rows.get(0);
        List<Map<String, Object>> lines = new ArrayList<>();
        List<Line> std = billing.standardLines(id, period);
        String stored = d == null ? null : (String) d.get("lines");
        if (stored != null) {
            lines = readLines(stored);
        } else {
            for (Line l : std) lines.add(lineJson(l.kind(), l.label(), l.amount(), l.amount()));
        }
        Map<String, Object> disc = new LinkedHashMap<>();
        disc.put("t", d == null ? "none" : d.get("disc_type"));
        disc.put("offer", d == null || d.get("offer_id") == null ? "" : d.get("offer_id").toString());
        disc.put("val", d == null ? 0 : ((BigDecimal) d.get("disc_value")).intValue());
        disc.put("reason", d == null ? "" : d.get("disc_reason"));
        disc.put("months", d == null ? 1 : ((Number) d.get("disc_months")).intValue());

        Map<String, Object> m = new LinkedHashMap<>();
        m.put("id", id.toString());
        m.put("name", a.get("name"));
        m.put("plan", a.get("plan"));
        m.put("planName", a.get("plan_name"));
        m.put("skip", d != null && (Boolean) d.get("skip"));
        m.put("keep", d != null && (Boolean) d.get("keep_lines"));
        m.put("note", d == null ? "" : d.get("note"));
        m.put("lines", lines);
        m.put("edited", lines.stream().anyMatch(l -> "CUSTOM".equals(l.get("kind")) || ((Number) l.get("amount")).intValue() != ((Number) l.get("standard")).intValue()));
        m.put("disc", disc);
        m.put("totals", totals(lines, disc, gst));
        m.put("owes", overdue(id));
        m.put("to", recipients(id, a));
        return m;
    }

    private Map<String, Object> totals(List<Map<String, Object>> lines, Map<String, Object> disc, BigDecimal gst) {
        BigDecimal all = BigDecimal.ZERO, rec = BigDecimal.ZERO, plan = BigDecimal.ZERO;
        for (var l : lines) {
            BigDecimal amt = BigDecimal.valueOf(((Number) l.get("amount")).longValue());
            all = all.add(amt);
            String k = (String) l.get("kind");
            if (k.equals("PLAN") || k.equals("ADDON")) rec = rec.add(amt);
            if (k.equals("PLAN")) plan = plan.add(amt);
        }
        BigDecimal ds = discount(disc, rec, plan);
        BigDecimal sub = all.subtract(ds).max(BigDecimal.ZERO);
        BigDecimal tax = sub.multiply(gst).divide(BigDecimal.valueOf(100), 0, RoundingMode.HALF_UP);
        Map<String, Object> t = new LinkedHashMap<>();
        t.put("all", all);
        t.put("disc", ds);
        t.put("sub", sub);
        t.put("gst", tax);
        t.put("tot", sub.add(tax));
        return t;
    }

    /** What the discount takes off, given recurring charges [rec] and the plan charge [plan]. */
    private BigDecimal discount(Map<String, Object> disc, BigDecimal rec, BigDecimal plan) {
        String t = str(disc.get("t"));
        BigDecimal val = disc.get("val") instanceof Number n ? BigDecimal.valueOf(n.doubleValue()) : BigDecimal.ZERO;
        switch (t) {
            case "offer": {
                String id = str(disc.get("offer"));
                if (id.isEmpty()) return BigDecimal.ZERO;
                var o = jdbc.queryForList("SELECT type, value FROM hq_offers WHERE id = ?::uuid", id).stream().findFirst();
                if (o.isEmpty()) return BigDecimal.ZERO;
                BigDecimal v = (BigDecimal) o.get().get("value");
                return switch ((String) o.get().get("type")) {
                    case "PCT" -> rec.multiply(v).divide(BigDecimal.valueOf(100), 0, RoundingMode.HALF_UP);
                    case "FLAT" -> v.min(rec);
                    default -> plan;
                };
            }
            case "pct":
                return rec.multiply(val.max(BigDecimal.ZERO).min(BigDecimal.valueOf(100))).divide(BigDecimal.valueOf(100), 0, RoundingMode.HALF_UP);
            case "flat":
                return val.max(BigDecimal.ZERO).setScale(0, RoundingMode.HALF_UP).min(rec);
            default:
                return BigDecimal.ZERO;
        }
    }

    private List<Map<String, Object>> activeOffers() {
        return jdbc.queryForList("""
                SELECT id::text AS id, name, code, type, value, applies_to FROM hq_offers
                WHERE active AND starts_on <= current_date AND ends_on >= current_date ORDER BY name""");
    }

    private Map<String, Object> templateInfo() {
        var t = templates.billTemplate();
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("exists", t != null && !String.valueOf(t.get("body")).isBlank());
        m.put("on", t != null && Boolean.TRUE.equals(t.get("on")));
        m.put("title", t == null ? "" : t.get("title"));
        m.put("body", t == null ? "" : t.get("body"));
        return m;
    }

    private BigDecimal overdue(UUID academyId) {
        BigDecimal v = jdbc.queryForObject("""
                SELECT COALESCE(SUM(i.total - COALESCE((SELECT SUM(p.amount) FROM invoice_payments p WHERE p.invoice_id = i.id), 0)), 0)
                FROM academy_invoices i WHERE i.academy_id = ? AND i.status <> 'WAIVED' AND i.due_on < current_date""", BigDecimal.class, academyId);
        return v == null ? BigDecimal.ZERO : v.max(BigDecimal.ZERO);
    }

    /** The owner and the academy admin logins, one entry per distinct email. */
    private List<Map<String, Object>> recipients(UUID academyId, Map<String, Object> academy) {
        Map<String, Map<String, Object>> byEmail = new LinkedHashMap<>();
        String oe = str(academy.get("owner_email")).trim();
        if (!oe.isEmpty()) byEmail.put(oe.toLowerCase(), person(str(academy.get("owner_name")), oe, str(academy.get("owner_phone")), "Owner"));
        for (var r : jdbc.queryForList("""
                SELECT DISTINCT u.id, u.full_name, u.email FROM academy_memberships m JOIN users u ON u.id = m.user_id
                WHERE m.academy_id = ? AND m.role_type = 'ACADEMY_ADMIN' AND m.status = 'ACTIVE' AND u.email IS NOT NULL AND u.email <> ''""", academyId)) {
            byEmail.putIfAbsent(str(r.get("email")).toLowerCase(), person(str(r.get("full_name")), str(r.get("email")), "", "Academy admin login"));
        }
        return new ArrayList<>(byEmail.values());
    }

    private static Map<String, Object> person(String name, String email, String phone, String role) {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("name", name);
        m.put("email", email);
        m.put("phone", phone);
        m.put("role", role);
        return m;
    }

    // ---- drafts ----

    @Transactional
    public void saveDraft(UUID academyId, Map<String, Object> b) {
        String period = nextPeriod();
        var academy = billing.billable(period, academyId).stream().findFirst()
                .orElseThrow(() -> new ResourceNotFoundException("That academy has no bill waiting this month."));
        List<Line> std = billing.standardLines(academyId, period);

        boolean skip = Boolean.TRUE.equals(b.get("skip")), keep = Boolean.TRUE.equals(b.get("keep"));
        String note = str(b.get("note")).trim();
        if (note.length() > 140) throw new BadRequestException("Keep the note to 140 characters.");

        List<Map<String, Object>> lines = null;
        if (b.get("lines") instanceof List<?> raw) {
            lines = new ArrayList<>();
            boolean plan = false;
            for (Object o : raw) {
                if (!(o instanceof Map<?, ?> lm)) throw new BadRequestException("A charge is not readable.");
                String kind = str(lm.get("kind"));
                String label = str(lm.get("label")).trim();
                if (!LINE_KINDS.contains(kind)) throw new BadRequestException("A charge has an unknown kind.");
                if (label.length() < 3 || label.length() > 40) throw new BadRequestException("Name each charge in 3 to 40 characters.");
                long amount = lm.get("amount") instanceof Number n ? Math.round(n.doubleValue()) : -1;
                if (amount < 0 || amount > 10_000_000) throw new BadRequestException("Enter an amount for " + label + ".");
                if (kind.equals("CUSTOM") && amount == 0) throw new BadRequestException("A added charge must be above zero.");
                if (kind.equals("PLAN")) plan = true;
                long standard = lm.get("standard") instanceof Number n ? Math.round(n.doubleValue()) : amount;
                lines.add(lineJson(kind, label, BigDecimal.valueOf(amount), BigDecimal.valueOf(standard)));
            }
            if (!plan) throw new BadRequestException("The plan charge stays on the bill. You can change its amount.");
            // Identical to the standard bill: nothing to remember.
            boolean same = lines.size() == std.size();
            for (int i = 0; same && i < lines.size(); i++) {
                same = lines.get(i).get("label").equals(std.get(i).label()) && ((Number) lines.get(i).get("amount")).longValue() == std.get(i).amount().longValue();
            }
            if (same) lines = null;
        }

        @SuppressWarnings("unchecked") Map<String, Object> disc = b.get("disc") instanceof Map<?, ?> m ? (Map<String, Object>) m : Map.of("t", "none");
        String dt = str(disc.get("t"));
        if (!Set.of("none", "offer", "pct", "flat").contains(dt)) throw new BadRequestException("Choose a kind of discount.");
        UUID offer = null;
        BigDecimal val = BigDecimal.ZERO;
        String reason = str(disc.get("reason")).trim();
        int months = intOf(disc.get("months"), 1);
        if (months < 1 || months > 12) throw new BadRequestException("A discount lasts 1 to 12 bills.");
        if (dt.equals("offer")) {
            if (str(disc.get("offer")).isEmpty()) throw new BadRequestException("Choose an offer.");
            offer = UUID.fromString(str(disc.get("offer")));
            var o = activeOffers().stream().filter(x -> x.get("id").equals(disc.get("offer"))).findFirst()
                    .orElseThrow(() -> new BadRequestException("That offer is not running."));
            String applies = (String) o.get("applies_to");
            if (!applies.equals("all") && !applies.equals(academy.get("plan"))) throw new BadRequestException("That offer is not for this plan.");
        } else if (dt.equals("pct") || dt.equals("flat")) {
            val = BigDecimal.valueOf(intOf(disc.get("val"), 0));
            if (val.signum() <= 0) throw new BadRequestException(dt.equals("pct") ? "Enter the percent off." : "Enter the amount off.");
            if (dt.equals("pct") && val.compareTo(BigDecimal.valueOf(100)) > 0) throw new BadRequestException("A discount cannot be more than 100%.");
            if (reason.length() > 40) throw new BadRequestException("Keep the reason to 40 characters.");
        }

        boolean blank = !skip && lines == null && dt.equals("none") && note.isEmpty() && !keep;
        if (blank) {
            jdbc.update("DELETE FROM hq_invoice_drafts WHERE academy_id = ?", academyId);
            return;
        }
        jdbc.update("""
                INSERT INTO hq_invoice_drafts (academy_id, skip, lines, keep_lines, disc_type, offer_id, disc_value, disc_reason, disc_months, note, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, now())
                ON CONFLICT (academy_id) DO UPDATE SET skip = EXCLUDED.skip, lines = EXCLUDED.lines, keep_lines = EXCLUDED.keep_lines,
                    disc_type = EXCLUDED.disc_type, offer_id = EXCLUDED.offer_id, disc_value = EXCLUDED.disc_value, disc_reason = EXCLUDED.disc_reason,
                    disc_months = EXCLUDED.disc_months, note = EXCLUDED.note, updated_at = now()""",
                academyId, skip, lines == null ? null : write(lines), keep, dt, offer, val, dt.equals("offer") || dt.equals("none") ? "" : reason, months, note);
        audit.log("invoicing", academyId, (skip ? "Skipped" : "Changed") + " the " + label(period) + " bill for " + academy.get("name"));
    }

    @Transactional
    public void resetDraft(UUID academyId) {
        jdbc.update("DELETE FROM hq_invoice_drafts WHERE academy_id = ?", academyId);
    }

    // ---- the run ----

    public record RunResult(String period, int created, int skipped, int sent, int notSent, List<String> warnings, String via, String notSetUp) {
        Map<String, Object> toJson() {
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("period", period);
            m.put("created", created);
            m.put("skipped", skipped);
            m.put("sent", sent);
            m.put("notSent", notSent);
            m.put("warnings", warnings);
            m.put("via", via);
            m.put("notSetUp", notSetUp);
            return m;
        }
    }

    /** A run started by hand for the next month. [send] false only makes the bills. */
    @Transactional
    public Map<String, Object> run(boolean send) {
        return runPeriod(nextPeriod(), send, "By hand").toJson();
    }

    @Transactional
    public RunResult runPeriod(String period, boolean send, String mode) {
        Settings s = settings();
        LocalDate today = LocalDate.now();
        BigDecimal gst = billing.gstRate();
        // Manual runs are dated today; an automatic run follows the schedule.
        int dueDays = mode.equals("Automatic") ? (int) Math.max(1, ChronoUnit.DAYS.between(today, s.dueDate(period))) : s.due();
        List<String> warnings = new ArrayList<>();
        List<UUID> made = new ArrayList<>();
        int skipped = 0;

        for (var a : billing.billable(period, null)) {
            UUID academyId = (UUID) a.get("id");
            var rows = jdbc.queryForList("SELECT * FROM hq_invoice_drafts WHERE academy_id = ?", academyId);
            var d = rows.isEmpty() ? null : rows.get(0);
            if (d != null && (Boolean) d.get("skip")) {
                skipped++;
                afterRun(academyId, d, false);
                continue;
            }
            List<UUID> ids = billing.generate(period, academyId, today, dueDays, false);
            if (ids.isEmpty()) continue;
            UUID invoice = ids.get(0);
            made.add(invoice);
            if (d != null) applyDraft(invoice, academyId, a, d, warnings);
            billing.recompute(invoice);
            if (d != null) afterRun(academyId, d, true);
        }

        if (!made.isEmpty() || skipped > 0) {
            jdbc.update("INSERT INTO hq_invoice_runs (period, run_by, mode) VALUES (?, ?, ?) ON CONFLICT (period) DO NOTHING", period, TenantContext.currentUserIdOrNull(), mode);
        }
        int sent = 0;
        String via = "", notSetUp = "";
        if (send && !made.isEmpty()) {
            var r = sendBills(made);
            sent = r.sent();
            via = r.via();
            notSetUp = r.notSetUp();
        }
        audit.log("invoicing", "Generated " + made.size() + " bills for " + label(period) + (send ? (sent > 0 ? " and sent them" : " (nothing sent, no channel is set up)") : ""));
        return new RunResult(period, made.size(), skipped, sent, made.size() - sent, warnings, via, notSetUp);
    }

    /** Turns one academy's saved changes into the real lines, discount and note of its new bill. */
    private void applyDraft(UUID invoice, UUID academyId, Map<String, Object> academy, Map<String, Object> d, List<String> warnings) {
        String stored = (String) d.get("lines");
        if (stored != null) {
            jdbc.update("DELETE FROM invoice_lines WHERE invoice_id = ?", invoice);
            for (var l : readLines(stored)) {
                String kind = (String) l.get("kind");
                jdbc.update("INSERT INTO invoice_lines (invoice_id, kind, label, amount) VALUES (?, ?, ?, ?)",
                        invoice, kind.equals("CUSTOM") ? "ADJUSTMENT" : kind, l.get("label"), BigDecimal.valueOf(((Number) l.get("amount")).longValue()));
            }
        }
        String type = (String) d.get("disc_type");
        if (type.equals("offer") && d.get("offer_id") != null) {
            try {
                billing.setOffer(invoice, (UUID) d.get("offer_id"));
            } catch (BadRequestException e) {
                warnings.add(academy.get("name") + ": " + e.getMessage());
            }
        } else if (type.equals("pct") || type.equals("flat")) {
            BigDecimal rec = BigDecimal.ZERO;
            for (var l : jdbc.queryForList("SELECT kind, amount FROM invoice_lines WHERE invoice_id = ?", invoice)) {
                if (l.get("kind").equals("PLAN") || l.get("kind").equals("ADDON")) rec = rec.add((BigDecimal) l.get("amount"));
            }
            Map<String, Object> disc = Map.of("t", type, "val", ((BigDecimal) d.get("disc_value")).intValue());
            BigDecimal off = discount(disc, rec, BigDecimal.ZERO);
            if (off.signum() > 0) {
                String reason = str(d.get("disc_reason")).trim();
                jdbc.update("INSERT INTO invoice_lines (invoice_id, kind, label, amount) VALUES (?, 'ADJUSTMENT', ?, ?)",
                        invoice, "Discount: " + (reason.isEmpty() ? "Special discount" : reason), off.negate());
            }
        }
        String note = str(d.get("note")).trim();
        if (!note.isEmpty()) jdbc.update("UPDATE academy_invoices SET note = ? WHERE id = ?", note, invoice);
    }

    /** After a run: kept charges stay, a multi-bill discount counts down, and one-off choices (skip, note) are cleared. */
    private void afterRun(UUID academyId, Map<String, Object> d, boolean billed) {
        boolean keep = (Boolean) d.get("keep_lines");
        String type = (String) d.get("disc_type");
        int months = ((Number) d.get("disc_months")).intValue();
        boolean discGoes = type.equals("none") || (billed && months <= 1);
        boolean keepsLines = keep && d.get("lines") != null;
        if (!keepsLines && discGoes) {
            jdbc.update("DELETE FROM hq_invoice_drafts WHERE academy_id = ?", academyId);
            return;
        }
        jdbc.update("""
                UPDATE hq_invoice_drafts SET skip = FALSE, note = '', lines = ?, keep_lines = ?, disc_type = ?, offer_id = ?, disc_value = ?, disc_reason = ?, disc_months = ?, updated_at = now()
                WHERE academy_id = ?""",
                keepsLines ? d.get("lines") : null, keepsLines, discGoes ? "none" : type, discGoes ? null : d.get("offer_id"),
                discGoes ? BigDecimal.ZERO : d.get("disc_value"), discGoes ? "" : d.get("disc_reason"), discGoes ? 1 : (billed ? months - 1 : months), academyId);
    }

    // ---- sending ----

    public record SendResult(int sent, String via, String notSetUp) {
    }

    /** Sends each of [invoiceIds] that is still unsent. A bill counts as sent only if someone was actually reached. */
    @Transactional
    public SendResult sendBills(List<UUID> invoiceIds) {
        Settings s = settings();
        Map<String, Boolean> ready = channels.ready();
        List<String> skipped = new ArrayList<>();
        boolean useMail = s.mail() && ready.get("mail"), useApp = s.app(), useWa = s.wa() && ready.get("wa");
        if (s.mail() && !ready.get("mail")) skipped.add("Email");
        if (s.wa() && !ready.get("wa")) skipped.add("WhatsApp");
        String notSetUp = String.join(" and ", skipped);
        if (!useMail && !useApp && !useWa) return new SendResult(0, "", notSetUp);

        int sent = 0;
        Set<String> viaAll = new LinkedHashSet<>();
        for (UUID id : invoiceIds) {
            var rows = jdbc.queryForList("""
                    SELECT i.id, i.number, i.period, i.total, i.discount, i.due_on, i.academy_id, i.sent_at, a.name AS academy, a.owner_name, a.owner_email, a.owner_phone, a.plan, p.display_name AS plan_name
                    FROM academy_invoices i JOIN academies a ON a.id = i.academy_id LEFT JOIN billing_plans p ON p.code = i.plan_code WHERE i.id = ?""", id);
            if (rows.isEmpty() || rows.get(0).get("sent_at") != null) continue;
            var i = rows.get(0);
            UUID academyId = (UUID) i.get("academy_id");
            String[] msg = message(i);
            Set<String> via = new LinkedHashSet<>();

            if (useApp) {
                List<UUID> admins = jdbc.queryForList("""
                        SELECT DISTINCT user_id FROM academy_memberships WHERE academy_id = ? AND role_type = 'ACADEMY_ADMIN' AND status = 'ACTIVE'""", UUID.class, academyId);
                for (UUID u : admins) notifications.notify(u, NotificationModule.ERP, NotificationType.ADMIN_BROADCAST, msg[0], msg[1], null);
                if (!admins.isEmpty()) via.add("Owleo Nest app");
            }
            if (useMail) {
                int reached = 0;
                for (var r : recipients(academyId, i)) {
                    try {
                        channels.sendMail((String) r.get("email"), msg[0], msg[1]);
                        reached++;
                    } catch (RuntimeException e) {
                        log.warn("Bill email to an academy admin failed: {}", e.getMessage());
                    }
                }
                if (reached > 0) via.add("Email");
            }
            if (via.isEmpty()) continue;
            jdbc.update("UPDATE academy_invoices SET sent_at = now(), sent_via = ?, sent_skipped = ? WHERE id = ?",
                    String.join(", ", via), notSetUp.isEmpty() ? null : notSetUp, id);
            audit.log("invoicing", academyId, "Sent the " + label((String) i.get("period")) + " bill " + i.get("number") + " on " + String.join(", ", via));
            viaAll.addAll(via);
            sent++;
        }
        return new SendResult(sent, String.join(", ", viaAll), notSetUp);
    }

    /** The bill message: the Monthly bill template when it is on, otherwise plain default wording. */
    private String[] message(Map<String, Object> i) {
        String period = (String) i.get("period");
        Map<String, String> v = new LinkedHashMap<>();
        String owner = str(i.get("owner_name")).trim();
        v.put("owner", owner.isEmpty() ? "there" : owner.split("\\s+")[0]);
        v.put("academy", str(i.get("academy")));
        v.put("month", label(period));
        v.put("invoice", str(i.get("number")));
        v.put("amount", HqBilling.inr((BigDecimal) i.get("total")));
        v.put("due_date", ((java.sql.Date) i.get("due_on")).toLocalDate().format(DAY));
        v.put("plan", str(i.get("plan_name")));
        v.put("discount", HqBilling.inr(i.get("discount") == null ? BigDecimal.ZERO : (BigDecimal) i.get("discount")));
        var t = templates.billTemplate();
        boolean use = t != null && Boolean.TRUE.equals(t.get("on")) && !str(t.get("body")).isBlank() && !str(t.get("title")).isBlank();
        String title = use ? str(t.get("title")) : "Your {month} Owleo bill";
        String body = use ? str(t.get("body")) : "Hi {owner}, the {month} bill {invoice} for {academy} is ready. Amount to pay {amount}, due on {due_date}.";
        return new String[]{HqNotifications.fill(title, v), HqNotifications.fill(body, v)};
    }

    @Transactional
    public Map<String, Object> sendOne(UUID invoiceId) {
        SendResult r = sendBills(List.of(invoiceId));
        if (r.sent() == 0) {
            throw new BadRequestException(settings().app() || settings().mail() || settings().wa()
                    ? "Nobody could be reached. Check that the academy has an admin and that a channel is set up."
                    : "Pick a way to send in the schedule first.");
        }
        return Map.of("sent", r.sent(), "via", r.via());
    }

    @Transactional
    public Map<String, Object> sendRun(String period) {
        List<UUID> ids = jdbc.queryForList("SELECT id FROM academy_invoices WHERE period = ? AND sent_at IS NULL", UUID.class, period);
        SendResult r = sendBills(ids);
        return Map.of("sent", r.sent(), "notSent", ids.size() - r.sent(), "via", r.via(), "notSetUp", r.notSetUp());
    }

    // ---- history ----

    @Transactional(readOnly = true)
    public List<Map<String, Object>> history() {
        return jdbc.query("""
                SELECT i.period, count(*) AS bills, COALESCE(SUM(i.total), 0) AS total, count(i.sent_at) AS sent,
                       r.run_at, r.mode, u.full_name AS by_name
                FROM academy_invoices i LEFT JOIN hq_invoice_runs r ON r.period = i.period LEFT JOIN users u ON u.id = r.run_by
                GROUP BY i.period, r.run_at, r.mode, u.full_name ORDER BY i.period DESC LIMIT 24""", (rs, n) -> {
            Map<String, Object> m = new LinkedHashMap<>();
            String period = rs.getString("period");
            m.put("period", period);
            m.put("monthLabel", label(period));
            m.put("bills", rs.getInt("bills"));
            m.put("sent", rs.getInt("sent"));
            m.put("total", rs.getBigDecimal("total"));
            Timestamp at = rs.getTimestamp("run_at");
            m.put("at", at == null ? period + "-01" : at.toLocalDateTime().toLocalDate().toString());
            m.put("mode", rs.getString("mode") == null ? "Automatic" : rs.getString("mode"));
            m.put("by", rs.getString("by_name") == null ? "System" : rs.getString("by_name"));
            return m;
        });
    }

    @Transactional(readOnly = true)
    public List<Map<String, Object>> runBills(String period) {
        return jdbc.query("""
                SELECT i.id, i.number, i.total, i.sent_at, i.sent_via, a.name AS academy, a.id AS academy_id
                FROM academy_invoices i JOIN academies a ON a.id = i.academy_id WHERE i.period = ? ORDER BY a.name""", (rs, n) -> {
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("id", rs.getObject("id").toString());
            m.put("number", rs.getString("number"));
            m.put("academy", rs.getString("academy"));
            m.put("academyId", rs.getObject("academy_id").toString());
            m.put("total", rs.getBigDecimal("total"));
            m.put("sent", rs.getTimestamp("sent_at") != null);
            m.put("via", rs.getString("sent_via") == null ? "" : rs.getString("sent_via"));
            return m;
        }, period);
    }

    // ---- the daily job ----

    /** Runs the schedule for [today]: makes this month's bills on the generate day, and sends automatic runs when their send date arrives. */
    public void automatic(LocalDate today) {
        Settings s = settings();
        if (!s.auto()) return;
        String period = YearMonth.from(today).toString();
        boolean ran = !jdbc.queryForList("SELECT 1 FROM hq_invoice_runs WHERE period = ?", period).isEmpty();
        if (!ran && today.getDayOfMonth() >= s.gen()) {
            runPeriod(period, false, "Automatic");
        }
        for (var r : jdbc.queryForList("SELECT period FROM hq_invoice_runs WHERE mode = 'Automatic' AND period >= ? ORDER BY period",
                today.minusMonths(3).toString().substring(0, 7))) {
            String p = (String) r.get("period");
            if (!s.sendDate(p).isAfter(today)) {
                List<UUID> ids = jdbc.queryForList("SELECT id FROM academy_invoices WHERE period = ? AND sent_at IS NULL", UUID.class, p);
                if (!ids.isEmpty()) sendBills(ids);
            }
        }
    }

    // ---- helpers ----

    private static String label(String period) {
        return YearMonth.parse(period).format(MONTH);
    }

    private static Map<String, Object> lineJson(String kind, String label, BigDecimal amount, BigDecimal standard) {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("kind", kind);
        m.put("label", label);
        m.put("amount", amount.setScale(0, RoundingMode.HALF_UP).longValue());
        m.put("standard", standard.setScale(0, RoundingMode.HALF_UP).longValue());
        return m;
    }

    private List<Map<String, Object>> readLines(String stored) {
        try {
            return json.readValue(stored, new TypeReference<List<Map<String, Object>>>() {
            });
        } catch (Exception e) {
            return new ArrayList<>();
        }
    }

    private String write(Object o) {
        try {
            return json.writeValueAsString(o);
        } catch (Exception e) {
            throw new IllegalStateException(e);
        }
    }

    private static int intOf(Object o, int fallback) {
        if (o instanceof Number n) return n.intValue();
        try {
            return o == null ? fallback : Integer.parseInt(o.toString().trim());
        } catch (NumberFormatException e) {
            return fallback;
        }
    }

    private static String str(Object o) {
        return o == null ? "" : o.toString();
    }
}
