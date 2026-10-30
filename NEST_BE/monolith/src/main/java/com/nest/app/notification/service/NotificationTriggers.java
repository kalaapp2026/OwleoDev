package com.nest.app.notification.service;

import com.nest.app.curriculum.entity.Course;
import com.nest.app.curriculum.repository.CourseRepository;
import com.nest.app.enrolment.entity.Batch;
import com.nest.app.enrolment.entity.BatchMember;
import com.nest.app.enrolment.repository.BatchMemberRepository;
import com.nest.app.enrolment.repository.BatchRepository;
import com.nest.app.enrolment.repository.BatchTrainerRepository;
import com.nest.app.identity.entity.AcademyMembership;
import com.nest.app.identity.repository.AcademyMembershipRepository;
import com.nest.app.notification.entity.NotificationEvent;
import com.nest.app.scheduling.entity.ClassInstance;
import com.nest.app.scheduling.repository.ClassInstanceRepository;
import org.springframework.stereotype.Component;

import java.math.BigDecimal;
import java.text.NumberFormat;
import java.time.LocalDate;
import java.time.LocalTime;
import java.time.format.DateTimeFormatter;
import java.util.Collection;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;

/**
 * Where business events turn into notifications: resolves who should hear about it and what the
 * placeholder values are, then hands off to {@link NotificationDispatcher}. Business services call
 * one intent-named method here instead of knowing about audiences, formatting or templates.
 *
 * <p>Audience scoping is the thing to get right: each method notifies only the people the event is
 * actually about (a batch's students, one student), never the whole academy.</p>
 */
@Component
public class NotificationTriggers {

    private static final DateTimeFormatter DATE = DateTimeFormatter.ofPattern("d MMM", Locale.ENGLISH);
    private static final DateTimeFormatter TIME = DateTimeFormatter.ofPattern("h:mm a", Locale.ENGLISH);

    private final NotificationDispatcher dispatcher;
    private final BatchRepository batchRepository;
    private final BatchMemberRepository batchMemberRepository;
    private final AcademyMembershipRepository membershipRepository;
    private final CourseRepository courseRepository;
    private final ClassInstanceRepository classInstanceRepository;
    private final BatchTrainerRepository batchTrainerRepository;

    public NotificationTriggers(NotificationDispatcher dispatcher, BatchRepository batchRepository,
                                BatchMemberRepository batchMemberRepository,
                                AcademyMembershipRepository membershipRepository,
                                CourseRepository courseRepository, ClassInstanceRepository classInstanceRepository,
                                BatchTrainerRepository batchTrainerRepository) {
        this.dispatcher = dispatcher;
        this.batchRepository = batchRepository;
        this.batchMemberRepository = batchMemberRepository;
        this.membershipRepository = membershipRepository;
        this.courseRepository = courseRepository;
        this.classInstanceRepository = classInstanceRepository;
        this.batchTrainerRepository = batchTrainerRepository;
    }

    public void classRescheduled(UUID batchId, LocalDate oldDate, LocalDate newDate, LocalTime newStart, String reason) {
        Batch batch = batchRepository.findById(batchId).orElse(null);
        if (batch == null) return;
        Map<String, String> params = new HashMap<>();
        params.put("batchName", batch.getName());
        params.put("oldDate", format(oldDate));
        params.put("newDate", format(newDate));
        params.put("newTime", format(newStart));
        params.put("reason", reason == null ? "" : reason);
        dispatcher.fire(NotificationEvent.CLASS_RESCHEDULED, batchStudentUserIds(batchId), params);
    }

    public void classCancelled(UUID batchId, LocalDate date, LocalTime start, String reason) {
        Batch batch = batchRepository.findById(batchId).orElse(null);
        if (batch == null) return;
        Map<String, String> params = new HashMap<>();
        params.put("batchName", batch.getName());
        params.put("date", format(date));
        params.put("time", format(start));
        params.put("reason", reason == null ? "" : reason);
        dispatcher.fire(NotificationEvent.CLASS_CANCELLED, batchStudentUserIds(batchId), params);
    }

    /** How many people a class reminder reached, split so the confirmation can say who. */
    public record ReminderReach(int students, int trainers) {
        public int total() { return students + trainers; }
    }

    /**
     * "This is your next class", to the batch's students and whoever is teaching this session -
     * the substitute when there is one, the batch's own trainers otherwise. Sent even without a
     * Super Admin template: the person pressed a button and expects it to arrive.
     */
    public ReminderReach classReminder(ClassInstance instance) {
        Batch batch = batchRepository.findById(instance.getBatchId()).orElse(null);
        if (batch == null) return new ReminderReach(0, 0);
        String courseName = courseRepository.findAllById(batch.allCourseIds()).stream()
                .map(Course::getName).sorted().collect(java.util.stream.Collectors.joining(", "));
        if (courseName.isBlank()) courseName = "your course";

        Set<UUID> studentUserIds = new java.util.HashSet<>(batchStudentUserIds(batch.getId()));
        Collection<UUID> trainerMembershipIds = instance.getSubstituteTrainerMembershipId() != null
                ? List.of(instance.getSubstituteTrainerMembershipId())
                : batchTrainerRepository.findByBatchId(batch.getId()).stream()
                        .map(t -> t.getTrainerMembershipId()).toList();
        Set<UUID> trainerUserIds = membershipRepository.findAllById(trainerMembershipIds).stream()
                .map(AcademyMembership::getUserId).collect(Collectors.toSet());
        // Somebody who is both (a trainer who also attends another batch) is told once.
        studentUserIds.removeAll(trainerUserIds);

        Map<String, String> params = new HashMap<>();
        params.put("batchName", batch.getName());
        params.put("courseName", courseName);
        params.put("date", format(instance.getDate()));
        params.put("time", format(instance.getStartTime()));

        Set<UUID> everyone = new java.util.LinkedHashSet<>(trainerUserIds);
        everyone.addAll(studentUserIds);
        dispatcher.fireOrDefault(NotificationEvent.CLASS_REMINDER, everyone, params);
        return new ReminderReach(studentUserIds.size(), trainerUserIds.size());
    }

    /** One absence, told to that student only. */
    public void attendanceAbsent(UUID classInstanceId, UUID membershipId) {
        ClassInstance instance = classInstanceRepository.findById(classInstanceId).orElse(null);
        AcademyMembership membership = membershipRepository.findById(membershipId).orElse(null);
        if (instance == null || membership == null) return;
        String batchName = batchRepository.findById(instance.getBatchId()).map(Batch::getName).orElse("class");
        dispatcher.fire(NotificationEvent.ATTENDANCE_ABSENT, List.of(membership.getUserId()),
                Map.of("batchName", batchName, "date", format(instance.getDate())));
    }

    public void feePaymentReceived(UUID membershipId, UUID courseId, BigDecimal amount, String period, String mode) {
        AcademyMembership membership = membershipRepository.findById(membershipId).orElse(null);
        if (membership == null) return;
        String courseName = courseRepository.findById(courseId).map(Course::getName).orElse("your course");
        Map<String, String> params = new HashMap<>();
        params.put("amount", "Rs " + NumberFormat.getNumberInstance(new Locale("en", "IN")).format(amount));
        params.put("courseName", courseName);
        params.put("period", period);
        params.put("mode", mode == null ? "" : mode);
        dispatcher.fire(NotificationEvent.FEE_PAYMENT_RECEIVED, List.of(membership.getUserId()), params);
    }

    private Set<UUID> batchStudentUserIds(UUID batchId) {
        Collection<UUID> membershipIds = batchMemberRepository.findByBatchId(batchId).stream()
                .map(BatchMember::getMembershipId).collect(Collectors.toSet());
        return membershipRepository.findAllById(membershipIds).stream()
                .map(AcademyMembership::getUserId).collect(Collectors.toSet());
    }

    private static String format(LocalDate d) {
        return d == null ? "" : DATE.format(d);
    }

    private static String format(LocalTime t) {
        return t == null ? "" : TIME.format(t);
    }
}
