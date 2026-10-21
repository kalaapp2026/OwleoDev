package com.nest.app.hq.service;

import com.nest.app.hq.HqAudit;
import com.nest.app.hq.service.HqNotificationCatalogue.Ev;
import com.nest.app.hq.service.HqNotificationCatalogue.Mod;
import com.nest.app.notification.entity.NotificationEvent;
import com.nest.app.notification.entity.NotificationModule;
import com.nest.app.notification.entity.NotificationType;
import com.nest.app.notification.service.NotificationService;
import com.nest.common.exception.BadRequestException;
import com.nest.common.exception.ResourceNotFoundException;
import com.nest.common.security.TenantContext;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.sql.Timestamp;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Notification templates: the wording, channels and audience the Super Admin designs and links to a module.
 * What is stored here is the design; what the platform has actually sent is read from the delivery log
 * (notification_deliveries). A channel that is not set up is saved and shown as such, never faked.
 */
@Service
public class HqNotifications {

    private static final Pattern VAR = Pattern.compile("\\{(\\w+)}");
    private static final String SEEDED = "notif_templates_seeded";

    private final JdbcTemplate jdbc;
    private final HqAudit audit;
    private final HqChannels channels;
    private final NotificationService notifications;

    public HqNotifications(JdbcTemplate jdbc, HqAudit audit, HqChannels channels, NotificationService notifications) {
        this.jdbc = jdbc;
        this.audit = audit;
        this.channels = channels;
        this.notifications = notifications;
    }

    // ---- reading ----

    @Transactional
    public Map<String, Object> overview() {
        seedOnce();
        List<Map<String, Object>> templates = jdbc.query("SELECT * FROM hq_notification_templates ORDER BY created_at, name", (rs, i) -> toJson(rs));
        long on = templates.stream().filter(t -> Boolean.TRUE.equals(t.get("on")) && !str(t.get("body")).isBlank()).count();
        long conf = templates.stream().filter(t -> !str(t.get("body")).isBlank() && !str(t.get("title")).isBlank()).count();

        Map<String, Object> counts = new LinkedHashMap<>();
        counts.put("on", on);
        counts.put("written", conf);
        counts.put("all", templates.size());
        counts.put("sentToday", count("SELECT count(*) FROM notification_deliveries WHERE status = 'SENT' AND created_at >= current_date"));
        counts.put("skipped", count("SELECT count(*) FROM notification_deliveries WHERE status = 'SKIPPED' AND created_at > now() - interval '7 days'"));
        counts.put("failed", count("SELECT count(*) FROM notification_deliveries WHERE status = 'FAILED' AND created_at > now() - interval '7 days'"));

        Map<String, Object> out = new LinkedHashMap<>(HqNotificationCatalogue.asJson());
        out.put("ready", channels.ready());
        out.put("counts", counts);
        out.put("templates", templates);
        return out;
    }

    /** The delivery log, newest first: one row per template, channel and minute. [status] is all, sent, skipped or failed. */
    public List<Map<String, Object>> log(String status) {
        String st = status == null ? "all" : status.toLowerCase();
        List<Object> args = new ArrayList<>();
        String where = "";
        if (!st.equals("all")) {
            if (!Set.of("sent", "skipped", "failed").contains(st)) throw new BadRequestException("Unknown status.");
            where = " AND status = ?";
            args.add(st.toUpperCase());
        }
        return jdbc.query("""
                SELECT event_key, channel, status, max(detail) AS detail, count(DISTINCT user_id) AS n, date_trunc('minute', created_at) AS at
                FROM notification_deliveries WHERE created_at > now() - interval '14 days'""" + where + """
                 GROUP BY event_key, channel, status, date_trunc('minute', created_at)
                ORDER BY at DESC LIMIT 100""", (rs, i) -> {
            Map<String, Object> m = new LinkedHashMap<>();
            String key = rs.getString("event_key");
            m.put("name", eventName(key));
            m.put("channel", channelLabel(rs.getString("channel")));
            m.put("status", rs.getString("status").toLowerCase());
            m.put("people", rs.getInt("n"));
            m.put("detail", rs.getString("detail") == null ? "" : rs.getString("detail"));
            m.put("at", rs.getTimestamp("at").toLocalDateTime().atZone(java.time.ZoneId.systemDefault()).toInstant());
            return m;
        }, args.toArray());
    }

    // ---- writing ----

    @Transactional
    public Map<String, Object> save(UUID id, Map<String, Object> b) {
        Draft d = validated(b);
        UUID target = id;
        if (id == null) {
            target = UUID.randomUUID();
            jdbc.update("INSERT INTO hq_notification_templates (id, module, event, name) VALUES (?, ?, ?, ?)", target, d.module, d.event, d.name);
        } else if (jdbc.queryForList("SELECT 1 FROM hq_notification_templates WHERE id = ?", id).isEmpty()) {
            throw new ResourceNotFoundException("Template not found.");
        }
        jdbc.update("""
                UPDATE hq_notification_templates SET module = ?, event = ?, name = ?, audience = ?, enabled = ?,
                    ch_inapp = ?, ch_push = ?, ch_wa = ?, ch_mail = ?, title = ?, body = ?, timing = ?, user_types = ?,
                    par_on = ?, par_minors = ?, par_diff = ?, par_title = ?, par_body = ?, updated_at = now() WHERE id = ?""",
                d.module, d.event, d.name, d.audience, d.on, d.inapp, d.push, d.wa, d.mail, d.title, d.body, d.timing, d.types,
                d.parOn, d.parMinors, d.parDiff, d.parTitle, d.parBody, target);
        audit.log("notifs", (id == null ? "Added" : "Edited") + " notification template " + d.name);
        return jdbc.queryForObject("SELECT * FROM hq_notification_templates WHERE id = ?", (rs, i) -> toJson(rs), target);
    }

    @Transactional
    public void delete(UUID id) {
        List<String> n = jdbc.queryForList("SELECT name FROM hq_notification_templates WHERE id = ?", String.class, id);
        if (n.isEmpty()) throw new ResourceNotFoundException("Template not found.");
        jdbc.update("DELETE FROM hq_notification_templates WHERE id = ?", id);
        audit.log("notifs", "Deleted notification template " + n.get(0));
    }

    /**
     * Sends the message in the editor to the signed-in person only, with sample details filled in. In-app goes to
     * their Owleo Nest bell and email to their address when email is set up; the other channels are logged as
     * skipped, because a test should never reach anyone else.
     */
    @Transactional
    public List<Map<String, Object>> test(Map<String, Object> b) {
        String module = str(b.get("module"));
        Mod mod = HqNotificationCatalogue.module(module).orElseThrow(() -> new BadRequestException("Choose a module."));
        String title = str(b.get("title")).trim(), body = str(b.get("body")).trim();
        if (title.isEmpty() || body.isEmpty()) throw new BadRequestException("Write a title and message first.");
        @SuppressWarnings("unchecked") Map<String, Object> ch = b.get("ch") instanceof Map<?, ?> m ? (Map<String, Object>) m : Map.of();
        UUID me = TenantContext.currentUserId();
        String fTitle = plain(title, mod), fBody = plain(body, mod);
        String label = str(b.get("name")).isBlank() ? mod.name() : str(b.get("name")).trim();

        List<Map<String, Object>> out = new ArrayList<>();
        boolean security = module.equals("security");
        if (!security && Boolean.TRUE.equals(ch.get("inapp"))) {
            notifications.notify(me, NotificationModule.ERP, NotificationType.ADMIN_BROADCAST, fTitle, fBody, null);
            out.add(result("inapp", "sent", "Sent to your Owleo Nest bell"));
        }
        if (Boolean.TRUE.equals(ch.get("mail"))) {
            if (!channels.mailReady()) {
                out.add(result("mail", "skipped", "Email is not set up"));
            } else {
                List<String> to = jdbc.queryForList("SELECT email FROM users WHERE id = ?", String.class, me);
                if (to.isEmpty() || to.get(0) == null || to.get(0).isBlank()) {
                    out.add(result("mail", "skipped", "Your account has no email address"));
                } else {
                    try {
                        channels.sendMail(to.get(0), fTitle, fBody);
                        out.add(result("mail", "sent", "Sent to " + to.get(0)));
                    } catch (RuntimeException e) {
                        out.add(result("mail", "failed", "The mail server refused it"));
                    }
                }
            }
        }
        for (String c : List.of("push", "wa")) {
            if (Boolean.TRUE.equals(ch.get(c))) {
                out.add(result(c, "skipped", c.equals("push") ? "Test sends use the app and email only" : "WhatsApp tests are not sent, to protect message quality"));
            }
        }
        if (out.isEmpty()) throw new BadRequestException("Pick at least one channel to test.");
        for (var r : out) {
            if (r.get("channel").equals("mail")) continue; // the delivery log has no email column yet; the result is returned instead
            jdbc.update("INSERT INTO notification_deliveries (id, user_id, event_key, channel, status, detail) VALUES (?, ?, 'HQ_TEST', ?, ?, ?)",
                    UUID.randomUUID(), me, dbChannel((String) r.get("channel")), ((String) r.get("status")).toUpperCase(), "Test of " + label + ": " + r.get("detail"));
        }
        return out;
    }

    // ---- the one lookup other modules use ----

    /** The Monthly bill template, or null if none is written. Invoicing sends this with each bill. */
    public Map<String, Object> billTemplate() {
        seedOnce();
        var l = jdbc.query("SELECT * FROM hq_notification_templates WHERE module = 'billing' AND event = 'invoice' ORDER BY created_at LIMIT 1", (rs, i) -> toJson(rs));
        return l.isEmpty() ? null : l.get(0);
    }

    /** Fills {details} from [values]; a detail with no value is left as it is so the gap is visible. */
    public static String fill(String text, Map<String, String> values) {
        Matcher m = VAR.matcher(text == null ? "" : text);
        StringBuilder sb = new StringBuilder();
        while (m.find()) {
            String v = values.get(m.group(1));
            m.appendReplacement(sb, Matcher.quoteReplacement(v == null ? m.group() : v));
        }
        m.appendTail(sb);
        return sb.toString();
    }

    // ---- validation ----

    private record Draft(String module, String event, String name, String audience, boolean on, boolean inapp, boolean push, boolean wa, boolean mail,
                         String title, String body, int timing, String types, boolean parOn, boolean parMinors, boolean parDiff, String parTitle, String parBody) {
    }

    private Draft validated(Map<String, Object> b) {
        String moduleId = str(b.get("module"));
        Mod mod = HqNotificationCatalogue.module(moduleId).orElseThrow(() -> new BadRequestException("Choose a module."));
        Ev ev = mod.event(str(b.get("event"))).orElseThrow(() -> new BadRequestException("Choose when it is sent."));
        String name = str(b.get("name")).trim();
        if (name.length() < 3) throw new BadRequestException("Give the template a name.");
        if (name.length() > 40) throw new BadRequestException("Keep the name to 40 characters.");
        String title = str(b.get("title")).trim(), body = str(b.get("body")).trim();
        if (title.length() > 60) throw new BadRequestException("The title can be 60 characters at most.");
        if (body.length() > 240) throw new BadRequestException("The message can be 240 characters at most.");
        boolean on = Boolean.TRUE.equals(b.get("on"));
        boolean security = moduleId.equals("security");

        String audience = security ? "self" : str(b.get("audience"));
        if (!security && HqNotificationCatalogue.AUDIENCES.stream().noneMatch(a -> a[0].equals(audience) && !a[0].equals("self"))) {
            throw new BadRequestException("Choose who gets it.");
        }

        @SuppressWarnings("unchecked") Map<String, Object> ch = b.get("ch") instanceof Map<?, ?> m ? (Map<String, Object>) m : Map.of();
        boolean inapp = Boolean.TRUE.equals(ch.get("inapp")), push = Boolean.TRUE.equals(ch.get("push"));
        boolean wa = Boolean.TRUE.equals(ch.get("wa")), mail = Boolean.TRUE.equals(ch.get("mail"));

        Map<String, Object> par = b.get("par") instanceof Map<?, ?> m ? castMap(m) : Map.of();
        boolean parCapable = HqNotificationCatalogue.PARENT_MODULES.contains(moduleId);
        boolean parOn = parCapable && Boolean.TRUE.equals(par.get("on"));
        boolean parDiff = parOn && Boolean.TRUE.equals(par.get("diff"));
        String parTitle = parDiff ? str(par.get("title")).trim() : "", parBody = parDiff ? str(par.get("body")).trim() : "";
        if (parTitle.length() > 60 || parBody.length() > 240) throw new BadRequestException("The parent message is too long.");

        Set<String> allowed = new LinkedHashSet<>();
        mod.vars().forEach(v -> allowed.add(v.key()));
        Set<String> bad = new LinkedHashSet<>();
        for (String t : List.of(title, body, parTitle, parBody)) {
            Matcher m = VAR.matcher(t);
            while (m.find()) if (!allowed.contains(m.group(1))) bad.add("{" + m.group(1) + "}");
        }
        if (!bad.isEmpty()) {
            throw new BadRequestException(String.join(", ", bad) + " is not available for " + mod.name() + ". Use the details listed under the message.");
        }

        if (on) {
            if (title.isEmpty() || body.isEmpty()) throw new BadRequestException("Write a title and message, or turn it off.");
            if (parDiff && (parTitle.isEmpty() || parBody.isEmpty())) throw new BadRequestException("Write the title and message for the parent, or switch to the same message.");
            if (!(inapp || push || wa || mail)) throw new BadRequestException("Pick at least one channel, or turn it off.");
            if (security) {
                String need = Map.of("otp", "otp", "reset", "reset_link").get(ev.key());
                if (need != null && !(title + " " + body).contains("{" + need + "}")) {
                    throw new BadRequestException("Add {" + need + "} to the message, or it will not reach them.");
                }
            }
        }
        if (security && (inapp || push)) throw new BadRequestException("Sign-in messages go by email or WhatsApp, not the app.");

        int timing = 0;
        if (ev.timingLabel() != null) {
            Object t = b.get("timing");
            try {
                timing = t instanceof Number n ? n.intValue() : Integer.parseInt(str(t).trim());
            } catch (NumberFormatException e) {
                throw new BadRequestException("Enter a whole number for the timing.");
            }
            if (timing <= 0 || timing > 999) throw new BadRequestException("Enter a whole number for the timing.");
        }

        String types = null;
        if (security && b.get("types") instanceof List<?> l) {
            List<String> valid = l.stream().map(Object::toString).filter(x -> HqNotificationCatalogue.USER_TYPES.stream().anyMatch(u -> u[0].equals(x))).distinct().toList();
            if (valid.isEmpty()) throw new BadRequestException("Keep at least one type of user.");
            types = valid.size() == HqNotificationCatalogue.USER_TYPES.size() ? null : String.join(",", valid);
        }
        return new Draft(moduleId, ev.key(), name, audience, on, inapp, push, wa, mail, title, body, timing, types,
                parOn, parOn && !Boolean.FALSE.equals(par.get("min")), parDiff, parTitle, parBody);
    }

    // ---- helpers ----

    private Map<String, Object> toJson(java.sql.ResultSet rs) throws java.sql.SQLException {
        Map<String, Object> m = new LinkedHashMap<>();
        String module = rs.getString("module"), event = rs.getString("event");
        m.put("id", rs.getObject("id").toString());
        m.put("module", module);
        m.put("event", event);
        m.put("name", rs.getString("name"));
        m.put("eventName", HqNotificationCatalogue.module(module).flatMap(x -> x.event(event)).map(Ev::name).orElse(event));
        m.put("audience", rs.getString("audience"));
        m.put("on", rs.getBoolean("enabled"));
        m.put("ch", Map.of("inapp", rs.getBoolean("ch_inapp"), "push", rs.getBoolean("ch_push"), "wa", rs.getBoolean("ch_wa"), "mail", rs.getBoolean("ch_mail")));
        m.put("title", rs.getString("title"));
        m.put("body", rs.getString("body"));
        m.put("timing", rs.getInt("timing"));
        String types = rs.getString("user_types");
        m.put("types", types == null ? null : Arrays.asList(types.split(",")));
        m.put("par", Map.of("on", rs.getBoolean("par_on"), "min", rs.getBoolean("par_minors"), "diff", rs.getBoolean("par_diff"),
                "title", rs.getString("par_title"), "body", rs.getString("par_body")));
        Timestamp u = rs.getTimestamp("updated_at");
        m.put("updatedAt", u == null ? null : u.toInstant());
        return m;
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> castMap(Map<?, ?> m) {
        return (Map<String, Object>) m;
    }

    private static String plain(String text, Mod mod) {
        Map<String, String> sample = new LinkedHashMap<>();
        mod.vars().forEach(v -> sample.put(v.key(), v.sample()));
        return fill(text, sample);
    }

    private static Map<String, Object> result(String channel, String status, String detail) {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("channel", channel);
        m.put("status", status);
        m.put("detail", detail);
        return m;
    }

    private static String dbChannel(String c) {
        return switch (c) {
            case "push" -> "PUSH";
            case "wa" -> "WHATSAPP";
            default -> "IN_APP";
        };
    }

    private static String channelLabel(String c) {
        return switch (c) {
            case "PUSH" -> "Push";
            case "WHATSAPP" -> "WhatsApp";
            case "EMAIL" -> "Email";
            default -> "In-app";
        };
    }

    private static String eventName(String key) {
        if ("HQ_TEST".equals(key)) return "Test send";
        try {
            return NotificationEvent.valueOf(key).getLabel();
        } catch (IllegalArgumentException e) {
            return key;
        }
    }

    private long count(String sql) {
        Long n = jdbc.queryForObject(sql, Long.class);
        return n == null ? 0 : n;
    }

    private static String str(Object o) {
        return o == null ? "" : o.toString();
    }

    // ---- the starting set ----

    /** Writes the first set of templates once, so the page opens with something to edit. Deleting them all keeps it empty. */
    private void seedOnce() {
        if (!jdbc.queryForList("SELECT 1 FROM hq_settings WHERE key = ?", SEEDED).isEmpty()) return;
        // module, event, audience, on, [inapp, push, wa, mail], title, body, timing, parent(on, minors, diff, title, body)
        seed("fees", "due_soon", "student", true, "1100", "Fee due soon", "Hi {student}, {amount} for {course} is due on {due_date}. Pay in the app to avoid a late mark.", 3, null);
        seed("fees", "overdue", "student", true, "1100", "Fee overdue", "Hi {student}, your fee of {amount} was due on {due_date}. Please pay soon. Invoice {invoice}.", 2,
                new String[]{"Fee overdue for {student}", "Dear {parent}, {student}'s fee of {amount} for {course} was due on {due_date} and is still unpaid. Please pay at the academy counter or reply to this message for a payment link. Invoice {invoice}."});
        seed("fees", "received", "student", true, "1001", "Payment received", "Thank you. We received {amount} for {course}. Invoice {invoice}.", 0, null);
        seed("classes", "scheduled", "student", true, "1100", "New class added", "{course} ({batch}) is on {date} at {time} with {trainer}.", 0, null);
        seed("classes", "rescheduled", "student", true, "1100", "Class rescheduled", "Your {course} class moved from {old_time} to {time} on {date}.", 0, null);
        seed("classes", "cancelled", "student", false, "0000", "", "", 0, null);
        seed("classes", "reminder", "student", true, "0100", "Class starts soon", "{course} starts at {time}. See you there, {student}.", 60, null);
        seed("attendance", "absent", "student", true, "1100", "You were marked absent", "Hi {student}, you were marked absent for {course} on {date}.", 0,
                new String[]{"{student} was absent today", "Dear {parent}, {student} was marked absent for {course} ({batch}) on {date}. Please let us know if this was planned."});
        seed("attendance", "low", "parent", true, "1100", "Attendance is low", "{student}'s attendance in {course} is {percent}. Regular practice matters.", 75, null);
        seed("messages", "broadcast", "all", true, "1100", "{title}", "{message}", 0, null);
        seed("events", "ticket", "student", true, "1000", "Ticket confirmed", "{tickets} ticket(s) for {event} on {date} at {venue}.", 0, null);
        seed("events", "reminder", "student", false, "0000", "", "", 24, null);
        seed("study", "new", "student", true, "1000", "New material in {course}", "{trainer} shared \"{material}\".", 0, null);
        seed("account", "welcome", "student", true, "1100", "Welcome to {academy}", "Hi {student}, you are all set for {course}.", 0, null);
        seed("security", "otp", "self", true, "0001", "Your sign-in code", "{otp} is your {academy} code. It works for {minutes} minutes. Never share it with anyone.", 10, null);
        seed("security", "reset", "self", true, "0001", "Reset your password", "Hi {name}, tap {reset_link} to choose a new password. The link works for {minutes} minutes. If you did not ask for this, ignore this message.", 30, null);
        seed("security", "changed", "self", true, "0001", "Your password was changed", "Hi {name}, your {academy} password was changed on {time}. If this was not you, reset it now.", 0, null);
        seed("billing", "invoice", "admin", true, "1001", "Your {month} Owleo bill",
                "Hi {owner}, the {month} bill {invoice} for {academy} ({plan} plan) is ready. Amount to pay {amount}, due on {due_date}. You can view and pay it from Billing in Owleo Nest.", 0, null);
        jdbc.update("INSERT INTO hq_settings (key, value) VALUES (?, '1') ON CONFLICT (key) DO NOTHING", SEEDED);
    }

    private void seed(String module, String event, String audience, boolean on, String ch, String title, String body, int timing, String[] parent) {
        Mod mod = HqNotificationCatalogue.module(module).orElseThrow();
        Ev ev = mod.event(event).orElseThrow();
        int t = ev.timingLabel() == null ? 0 : (timing > 0 ? timing : ev.timing());
        jdbc.update("""
                INSERT INTO hq_notification_templates (module, event, name, audience, enabled, ch_inapp, ch_push, ch_wa, ch_mail, title, body, timing,
                                                       par_on, par_minors, par_diff, par_title, par_body)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, TRUE, ?, ?, ?)""",
                module, event, ev.name(), audience, on, ch.charAt(0) == '1', ch.charAt(1) == '1', ch.charAt(2) == '1', ch.charAt(3) == '1', title, body, t,
                parent != null, parent != null, parent == null ? "" : parent[0], parent == null ? "" : parent[1]);
    }
}
