package com.nest.app.notification.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.time.Duration;
import java.time.Instant;

/** Clears notifications once they are old enough that nobody is looking for them (60 days by default). */
@Component
public class NotificationRetentionJob {

    private static final Logger log = LoggerFactory.getLogger(NotificationRetentionJob.class);

    private final NotificationService notificationService;
    private final int retentionDays;

    public NotificationRetentionJob(NotificationService notificationService,
                                    @Value("${nest.notifications.retention-days:60}") int retentionDays) {
        this.notificationService = notificationService;
        this.retentionDays = retentionDays;
    }

    @Scheduled(cron = "0 30 3 * * *")
    public void purge() {
        try {
            int removed = run(Instant.now());
            if (removed > 0) {
                log.info("Cleared {} notifications older than {} days", removed, retentionDays);
            }
        } catch (RuntimeException e) {
            log.error("Could not clear old notifications", e);
        }
    }

    /** Public so a test can run it for a chosen moment. Returns how many notifications were removed. */
    public int run(Instant now) {
        return notificationService.purgeOlderThan(now.minus(Duration.ofDays(retentionDays)));
    }
}
