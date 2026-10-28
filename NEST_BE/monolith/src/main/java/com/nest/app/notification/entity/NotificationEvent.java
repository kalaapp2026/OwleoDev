package com.nest.app.notification.entity;

import java.util.ArrayList;
import java.util.List;

/**
 * The catalogue of things the platform can notify about. It lives in code rather than the database
 * because an event is only real if some service fires it; the Super Admin configures the wording
 * and channels (see {@link NotificationTemplate}), not which events exist.
 *
 * <p>To add one: add a constant here, then call
 * {@code NotificationDispatcher.fire(...)} where it happens.</p>
 */
public enum NotificationEvent {

    CLASS_RESCHEDULED(NotificationModule.ERP, "Class rescheduled",
            "A session was moved to a new date or time. Sent to every student in the batch.", null,
            "Class rescheduled",
            "Hi {{recipientName}}, your {{batchName}} class on {{oldDate}} has moved to {{newDate}} at {{newTime}}. {{reason}}",
            "batchName", "oldDate", "newDate", "newTime", "reason"),

    CLASS_CANCELLED(NotificationModule.ERP, "Class cancelled",
            "A session was cancelled. Sent to every student in the batch.", null,
            "Class cancelled",
            "Hi {{recipientName}}, your {{batchName}} class on {{date}} at {{time}} is cancelled. {{reason}}",
            "batchName", "date", "time", "reason"),

    ATTENDANCE_ABSENT(NotificationModule.ERP, "Marked absent",
            "A student was marked absent. Sent to that student, if they have attendance alerts on.", "attendance",
            "Marked absent",
            "{{recipientName}} was marked absent from {{batchName}} on {{date}}.",
            "batchName", "date"),

    CLASS_REMINDER(NotificationModule.ERP, "Class reminder",
            "An admin or trainer pressed Remind on a class. Sent to the batch's students and the trainers teaching it.", null,
            "Class reminder",
            "Hi {{recipientName}}, reminder: this is your next class - {{batchName}} ({{courseName}}) on {{date}} at {{time}}.",
            "batchName", "courseName", "date", "time"),

    FEE_PAYMENT_RECEIVED(NotificationModule.ERP, "Fee payment received",
            "A fee payment was recorded. Sent to the student it was recorded against.", null,
            "Payment received",
            "Hi {{recipientName}}, we received {{amount}} for {{courseName}} ({{period}}). Thank you!",
            "amount", "courseName", "period", "mode");

    private final NotificationModule module;
    private final String label;
    private final String description;
    /** Which Settings > Notifications switch silences this event (attendance/events/study), or null. */
    private final String preferenceKey;
    private final String defaultTitle;
    private final String defaultBody;
    private final List<String> placeholders;

    NotificationEvent(NotificationModule module, String label, String description, String preferenceKey,
                      String defaultTitle, String defaultBody, String... eventPlaceholders) {
        this.module = module;
        this.label = label;
        this.description = description;
        this.preferenceKey = preferenceKey;
        this.defaultTitle = defaultTitle;
        this.defaultBody = defaultBody;
        // Can't read BUILT_IN_PLACEHOLDERS here: enum constants initialise before static fields.
        List<String> all = new ArrayList<>(List.of("recipientName"));
        all.addAll(List.of(eventPlaceholders));
        this.placeholders = List.copyOf(all);
    }

    public NotificationModule getModule() { return module; }
    public String getLabel() { return label; }
    public String getDescription() { return description; }
    public String getPreferenceKey() { return preferenceKey; }
    public String getDefaultTitle() { return defaultTitle; }
    public String getDefaultBody() { return defaultBody; }
    public List<String> getPlaceholders() { return placeholders; }
}
