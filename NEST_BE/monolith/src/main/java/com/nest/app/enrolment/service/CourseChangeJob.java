package com.nest.app.enrolment.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.event.EventListener;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.time.LocalDate;

/**
 * Applies scheduled course changes on their day.
 *
 * <p>Runs just after midnight, well before the 02:00 fee-slip run, so a student promoted on the 1st is
 * already on the new course when that day's slips are generated. It also runs once on startup: a free-tier
 * server that was asleep through the night catches up the moment it wakes, instead of waiting a day.
 */
@Component
public class CourseChangeJob {

    private static final Logger log = LoggerFactory.getLogger(CourseChangeJob.class);

    private final CourseChangeService courseChangeService;

    public CourseChangeJob(CourseChangeService courseChangeService) {
        this.courseChangeService = courseChangeService;
    }

    @Scheduled(cron = "0 20 0 * * *")
    public void nightly() {
        run();
    }

    @EventListener(ApplicationReadyEvent.class)
    public void onStartup() {
        run();
    }

    private void run() {
        try {
            int applied = courseChangeService.applyDue(LocalDate.now());
            if (applied > 0) {
                log.info("Applied {} scheduled course change(s)", applied);
            }
        } catch (RuntimeException e) {
            log.error("Applying scheduled course changes failed", e);
        }
    }
}
