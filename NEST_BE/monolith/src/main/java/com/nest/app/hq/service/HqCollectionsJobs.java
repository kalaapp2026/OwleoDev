package com.nest.app.hq.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.YearMonth;
import java.util.List;
import java.util.Map;
import java.util.UUID;

/**
 * The two things Collections does on its own: raise the month's bills on the 1st, and send the
 * automatic payment reminders the owner has switched on. Both are idempotent, so a restart or a
 * second run the same day does no harm.
 */
@Component
public class HqCollectionsJobs {

    private static final Logger log = LoggerFactory.getLogger(HqCollectionsJobs.class);

    private final HqBilling billing;
    private final JdbcTemplate jdbc;

    public HqCollectionsJobs(HqBilling billing, JdbcTemplate jdbc) {
        this.billing = billing;
        this.jdbc = jdbc;
    }

    @Scheduled(cron = "0 30 2 1 * *")
    public void raiseBills() {
        try {
            int n = billing.generate(YearMonth.now().toString());
            log.info("Raised {} bills for {}", n, YearMonth.now());
        } catch (RuntimeException e) {
            log.error("Could not raise this month's bills", e);
        }
    }

    @Scheduled(cron = "0 0 9 * * *")
    public void automaticReminders() {
        try {
            run(LocalDate.now());
        } catch (RuntimeException e) {
            log.error("Automatic payment reminders failed", e);
        }
    }

    /** Public so a test can run it for a chosen day. Returns how many reminders went out. */
    public int run(LocalDate today) {
        Map<String, Object> s = jdbc.queryForMap("SELECT before_3d, on_due, after_3d, weekly FROM hq_reminder_settings WHERE id = 1");
        boolean before = (Boolean) s.get("before_3d"), onDue = (Boolean) s.get("on_due"), after = (Boolean) s.get("after_3d"), weekly = (Boolean) s.get("weekly");
        if (!before && !onDue && !after && !weekly) {
            return 0;
        }
        int sent = 0;
        List<Map<String, Object>> open = jdbc.queryForList("""
                SELECT i.id, i.academy_id, i.number, i.due_on, a.name,
                       i.total - COALESCE((SELECT SUM(p.amount) FROM invoice_payments p WHERE p.invoice_id = i.id), 0) AS balance
                FROM academy_invoices i JOIN academies a ON a.id = i.academy_id
                WHERE i.status = 'DUE' AND a.closed_at IS NULL""");
        for (var b : open) {
            BigDecimal balance = (BigDecimal) b.get("balance");
            if (balance.signum() <= 0) continue;
            LocalDate due = ((java.sql.Date) b.get("due_on")).toLocalDate();
            long daysLate = java.time.temporal.ChronoUnit.DAYS.between(due, today);
            boolean hit = (before && daysLate == -3) || (onDue && daysLate == 0) || (after && daysLate == 3) || (weekly && daysLate > 0 && daysLate % 7 == 0);
            if (!hit) continue;
            String when = daysLate < 0 ? "is due on " + due : daysLate == 0 ? "is due today" : "was due on " + due + " and is " + daysLate + " days overdue";
            String msg = "Hi, this is Owleo. Your bill " + b.get("number") + " of " + HqBilling.inr(balance) + " " + when
                    + ". You can pay from Billing in your Owleo Nest app. Thank you!";
            billing.remind((UUID) b.get("academy_id"), List.of((UUID) b.get("id")), "Automatic", msg);
            sent++;
        }
        return sent;
    }
}
