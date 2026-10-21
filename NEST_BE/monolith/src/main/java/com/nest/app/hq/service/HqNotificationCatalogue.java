package com.nest.app.hq.service;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;

/**
 * What a notification template can be linked to: the modules, the moments inside each module, and the
 * details (variables) a message may use. It lives in code because a template is only meaningful for a moment
 * some service can name; the Super Admin writes the wording, not the list of moments.
 */
public final class HqNotificationCatalogue {

    private HqNotificationCatalogue() {
    }

    public record Var(String key, String label, String sample) {
    }

    /** timingLabel is null when the moment has no timing; otherwise what the number means, e.g. "days before the due date". */
    public record Ev(String key, String name, String text, String timingLabel, int timing) {
    }

    public record Mod(String id, String name, String icon, String tone, List<Var> vars, List<Ev> events) {
        public Optional<Ev> event(String key) {
            return events.stream().filter(e -> e.key().equals(key)).findFirst();
        }

        public Optional<Var> var(String key) {
            return vars.stream().filter(v -> v.key().equals(key)).findFirst();
        }

        /** The sender shown in a preview: Owleo for billing, otherwise the academy. */
        public String sender() {
            return id.equals("billing") ? "Owleo" : var("academy").map(Var::sample).orElse("Owleo");
        }
    }

    /** Audiences a template can be written for. 'self' is only for security messages. */
    public static final List<String[]> AUDIENCES = List.of(
            new String[]{"student", "Student"}, new String[]{"parent", "Parent or guardian"}, new String[]{"trainer", "Trainer"},
            new String[]{"admin", "Academy admin"}, new String[]{"all", "Everyone in the academy"}, new String[]{"self", "Anyone who signs in"});

    public static final List<String[]> USER_TYPES = List.of(
            new String[]{"student", "Students"}, new String[]{"parent", "Parents and guardians"}, new String[]{"trainer", "Trainers"},
            new String[]{"admin", "Academy admins"}, new String[]{"super", "Super admins"});

    /** Modules where the parent or guardian can also be messaged on WhatsApp. */
    public static final List<String> PARENT_MODULES = List.of("fees", "attendance", "classes");

    public static final List<String[]> CHANNELS = List.of(
            new String[]{"inapp", "In-app"}, new String[]{"push", "Push"}, new String[]{"wa", "WhatsApp"}, new String[]{"mail", "Email"});

    private static Var v(String k, String l, String s) {
        return new Var(k, l, s);
    }

    private static Ev e(String k, String n, String t) {
        return new Ev(k, n, t, null, 0);
    }

    private static Ev e(String k, String n, String t, String label, int timing) {
        return new Ev(k, n, t, label, timing);
    }

    public static final List<Mod> MODULES = List.of(
            new Mod("fees", "Fees", "rupee", "gold", List.of(
                    v("student", "Student name", "Aanya"), v("academy", "Academy name", "Nritya Dance Academy"), v("parent", "Parent or guardian name", "Mr. Rao"),
                    v("amount", "Amount", "₹2,400"), v("due_date", "Due date", "20 Oct"), v("invoice", "Invoice number", "INV-2410-118"), v("course", "Course", "Bharatanatyam")),
                    List.of(e("due_soon", "Fee due soon", "Before the due date.", "days before the due date", 3),
                            e("overdue", "Fee overdue", "After the due date passes with no payment.", "days after the due date", 1),
                            e("received", "Payment received", "As soon as a payment is recorded."))),
            new Mod("classes", "Classes", "cal", "primary", List.of(
                    v("student", "Student name", "Aanya"), v("academy", "Academy name", "Nritya Dance Academy"), v("course", "Course", "Bharatanatyam"),
                    v("batch", "Batch", "Sat 5 pm"), v("trainer", "Trainer", "Meera"), v("date", "Date", "Sat, 24 Oct"), v("time", "Time", "5:00 pm"),
                    v("old_time", "Earlier time", "4:00 pm"), v("parent", "Parent or guardian name", "Mr. Rao")),
                    List.of(e("scheduled", "Class scheduled", "A new session is added to a batch."),
                            e("rescheduled", "Class rescheduled", "A session moved to a new date or time."),
                            e("cancelled", "Class cancelled", "A session was cancelled."),
                            e("reminder", "Class reminder", "Shortly before a session starts.", "minutes before the class", 60))),
            new Mod("attendance", "Attendance", "check", "green", List.of(
                    v("student", "Student name", "Aanya"), v("academy", "Academy name", "Nritya Dance Academy"), v("course", "Course", "Bharatanatyam"),
                    v("batch", "Batch", "Sat 5 pm"), v("date", "Date", "Sat, 17 Oct"), v("parent", "Parent or guardian name", "Mr. Rao"), v("percent", "Attendance so far", "68%")),
                    List.of(e("absent", "Marked absent", "A student is marked absent."),
                            e("low", "Low attendance warning", "Attendance drops below the limit.", "percent attendance limit", 75))),
            new Mod("messages", "Messages", "msg", "blue", List.of(
                    v("student", "Student name", "Aanya"), v("academy", "Academy name", "Nritya Dance Academy"), v("sender", "Sent by", "Meera (trainer)"),
                    v("title", "Message title", "Annual day rehearsal"), v("message", "Message text", "Rehearsal moves to the main hall this Friday.")),
                    List.of(e("broadcast", "Broadcast message", "An admin or trainer sends a message to a group."),
                            e("reply", "Reply received", "Someone replies to a message."))),
            new Mod("events", "Events", "spark", "magenta", List.of(
                    v("student", "Name", "Aanya"), v("academy", "Academy name", "Nritya Dance Academy"), v("event", "Event", "Annual Day 2026"),
                    v("date", "Date", "Sun, 8 Nov"), v("time", "Time", "6:00 pm"), v("venue", "Venue", "Town Hall"), v("tickets", "Tickets", "2")),
                    List.of(e("ticket", "Ticket confirmed", "After a ticket purchase."),
                            e("reminder", "Event reminder", "Before an event starts.", "hours before the event", 24),
                            e("cancelled", "Event cancelled", "An event is cancelled."))),
            new Mod("study", "Study material", "book", "violet", List.of(
                    v("student", "Student name", "Aanya"), v("academy", "Academy name", "Nritya Dance Academy"), v("course", "Course", "Bharatanatyam"),
                    v("material", "Material", "Adavu practice video"), v("trainer", "Trainer", "Meera")),
                    List.of(e("new", "New material shared", "A trainer shares something new."))),
            new Mod("account", "Account", "user", "coral", List.of(
                    v("student", "Name", "Aanya"), v("academy", "Academy name", "Nritya Dance Academy"), v("course", "Course", "Bharatanatyam")),
                    List.of(e("welcome", "Welcome to the academy", "When someone joins."),
                            e("birthday", "Birthday wish", "On their birthday."))),
            new Mod("billing", "Billing", "wallet", "gold", List.of(
                    v("owner", "Owner name", "Ritika"), v("academy", "Academy name", "Owleo Performing Arts Academy"), v("month", "Bill month", "November 2026"),
                    v("invoice", "Bill number", "INV-2611-007"), v("amount", "Amount to pay", "₹2,949"), v("due_date", "Due date", "24 Nov"),
                    v("plan", "Plan", "Growth"), v("discount", "Discount", "₹250")),
                    List.of(e("invoice", "Monthly bill sent", "When the monthly bill is sent to academy admins."),
                            e("paid", "Payment received", "When an academy pays its bill."))),
            new Mod("security", "Sign-in and security", "lock", "red", List.of(
                    v("name", "Name", "Aanya"), v("academy", "Academy name", "Nritya Dance Academy"), v("otp", "One-time code", "482913"),
                    v("minutes", "Minutes it is valid", "10"), v("reset_link", "Password reset link", "owleo.app/r/k3x9"), v("device", "Device", "Chrome on Android"),
                    v("time", "Time", "Sat, 17 Oct, 6:42 pm")),
                    List.of(e("otp", "Sign-in code (OTP)", "Sent when someone asks for a one-time code to sign in or verify.", "minutes the code is valid", 10),
                            e("reset", "Password reset", "Sent when someone asks to reset their password.", "minutes the link is valid", 30),
                            e("changed", "Password changed", "Sent after a password is changed, in case it was not them."),
                            e("newdev", "New device sign-in", "Sent when an account is used on a device it has not used before."))),
            new Mod("custom", "Other", "flag", "mute", List.of(
                    v("student", "Name", "Aanya"), v("academy", "Academy name", "Nritya Dance Academy"), v("date", "Date", "Sat, 24 Oct")),
                    List.of(e("manual", "Sent by hand", "Sent when an admin chooses to."))));

    public static Optional<Mod> module(String id) {
        return MODULES.stream().filter(m -> m.id().equals(id)).findFirst();
    }

    /** The JSON the console renders its pickers and "tap a detail" chips from. */
    public static Map<String, Object> asJson() {
        List<Object> mods = new ArrayList<>();
        for (Mod m : MODULES) {
            Map<String, Object> o = new LinkedHashMap<>();
            o.put("id", m.id());
            o.put("name", m.name());
            o.put("icon", m.icon());
            o.put("tone", m.tone());
            o.put("sender", m.sender());
            o.put("parentCapable", PARENT_MODULES.contains(m.id()));
            o.put("vars", m.vars().stream().map(x -> Map.of("key", x.key(), "label", x.label(), "sample", x.sample())).toList());
            o.put("events", m.events().stream().map(x -> {
                Map<String, Object> ev = new LinkedHashMap<>();
                ev.put("key", x.key());
                ev.put("name", x.name());
                ev.put("text", x.text());
                ev.put("timingLabel", x.timingLabel());
                ev.put("timing", x.timing());
                return ev;
            }).toList());
            mods.add(o);
        }
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("modules", mods);
        out.put("audiences", AUDIENCES.stream().map(a -> Map.of("key", a[0], "label", a[1])).toList());
        out.put("userTypes", USER_TYPES.stream().map(a -> Map.of("key", a[0], "label", a[1])).toList());
        out.put("channels", CHANNELS.stream().map(a -> Map.of("key", a[0], "label", a[1])).toList());
        return out;
    }
}
