package com.nest.app.scheduling.service;

import com.nest.common.audit.Auditable;
import com.nest.app.enrolment.entity.Batch;
import com.nest.app.enrolment.repository.BatchRepository;
import com.nest.app.identity.service.CourseFeatureGuard;
import com.nest.app.notification.service.NotificationTriggers;
import com.nest.app.scheduling.dto.ClassReminderResponse;
import com.nest.app.scheduling.entity.ClassInstance;
import com.nest.app.scheduling.entity.ClassInstanceStatus;
import com.nest.app.scheduling.repository.ClassInstanceRepository;
import com.nest.common.exception.BadRequestException;
import com.nest.common.exception.ResourceNotFoundException;
import com.nest.common.security.FeatureKey;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Duration;
import java.time.Instant;
import java.time.LocalDate;
import java.util.UUID;

/**
 * The Dashboard's Remind button: tells a batch's students and the trainers teaching one session
 * that it is coming up.
 *
 * <p>Who may press it follows the Dashboard schedule card - anyone who holds Attendance, Reschedule
 * or Batch scheduling on the class's course (and the batch, if they were given only some of the
 * course's batches). The coarse gate on the controller is the union across courses; this is the
 * per-course check that stops a trainer reminding a batch they have no part in.
 */
@Service
public class ClassReminderService {

    /** Long enough that a double tap, or two admins at once, cannot send a batch the same push
     * twice; short enough that a genuinely late "we are starting" nudge is not blocked. */
    static final Duration COOLDOWN = Duration.ofMinutes(10);

    private final ClassInstanceRepository classInstanceRepository;
    private final BatchRepository batchRepository;
    private final CourseFeatureGuard courseFeatureGuard;
    private final NotificationTriggers notificationTriggers;

    public ClassReminderService(ClassInstanceRepository classInstanceRepository, BatchRepository batchRepository,
                                CourseFeatureGuard courseFeatureGuard, NotificationTriggers notificationTriggers) {
        this.classInstanceRepository = classInstanceRepository;
        this.batchRepository = batchRepository;
        this.courseFeatureGuard = courseFeatureGuard;
        this.notificationTriggers = notificationTriggers;
    }

    @Transactional
    @Auditable(action = "CLASS_REMINDER_SENT", entityType = "class_instance")
    public ClassReminderResponse remind(UUID classInstanceId) {
        ClassInstance instance = classInstanceRepository.findById(classInstanceId)
                .orElseThrow(() -> new ResourceNotFoundException("Class instance not found: " + classInstanceId));
        Batch batch = batchRepository.findById(instance.getBatchId())
                .orElseThrow(() -> new ResourceNotFoundException("Batch not found: " + instance.getBatchId()));

        courseFeatureGuard.assertBatchAccess(batch.allCourseIds(), batch.getId(),
                FeatureKey.ATTENDANCE, FeatureKey.RESCHEDULE, FeatureKey.BATCH_SCHEDULING);

        if (instance.getStatus() != ClassInstanceStatus.SCHEDULED) {
            throw new BadRequestException("Only a class that is going ahead can be reminded about");
        }
        // A day of slack either side of the server's own "today": it runs in UTC while the academy
        // does not, and this check is only about not reminding people of a class long gone.
        if (instance.getDate().isBefore(LocalDate.now().minusDays(1))) {
            throw new BadRequestException("That class has already happened");
        }

        Instant now = Instant.now();
        Instant last = instance.getLastReminderAt();
        if (last != null && Duration.between(last, now).compareTo(COOLDOWN) < 0) {
            long minutes = Math.max(1, Duration.between(last, now).toMinutes());
            throw new BadRequestException("A reminder for this class went out " + minutes
                    + (minutes == 1 ? " minute" : " minutes") + " ago");
        }

        NotificationTriggers.ReminderReach reach = notificationTriggers.classReminder(instance);
        if (reach.total() == 0) {
            throw new BadRequestException("Nobody is assigned to this batch yet, so there is no one to remind");
        }

        instance.setLastReminderAt(now);
        classInstanceRepository.save(instance);
        return new ClassReminderResponse(reach.students(), reach.trainers(), now);
    }
}
