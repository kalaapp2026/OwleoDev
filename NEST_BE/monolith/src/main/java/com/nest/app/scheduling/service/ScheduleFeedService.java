package com.nest.app.scheduling.service;

import com.nest.app.attendance.repository.AttendanceRepository;
import com.nest.app.curriculum.entity.Course;
import com.nest.app.curriculum.repository.CourseRepository;
import com.nest.app.enrolment.entity.Batch;
import com.nest.app.enrolment.entity.BatchMember;
import com.nest.app.enrolment.entity.BatchStatus;
import com.nest.app.enrolment.entity.BatchTrainer;
import com.nest.app.enrolment.repository.BatchMemberRepository;
import com.nest.app.enrolment.repository.BatchRepository;
import com.nest.app.enrolment.repository.BatchTrainerRepository;
import com.nest.app.identity.entity.AcademyMembership;
import com.nest.app.identity.entity.User;
import com.nest.app.identity.repository.AcademyMembershipRepository;
import com.nest.app.identity.repository.UserRepository;
import com.nest.app.identity.service.CourseFeatureGuard;
import com.nest.app.scheduling.dto.ScheduleEntryResponse;
import com.nest.app.scheduling.dto.ScheduleEntryStatus;
import com.nest.app.scheduling.entity.ClassInstance;
import com.nest.app.scheduling.entity.ClassInstanceStatus;
import com.nest.app.scheduling.repository.ClassInstanceRepository;
import com.nest.common.security.FeatureKey;
import com.nest.common.security.TenantContext;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;

/**
 * The Schedule screen's read model: every class in the active academy over a date window, already
 * joined to its batch, course and instructors.
 *
 * <p>Read-only and separate from {@link SchedulingService}, which owns the recurring pattern, and
 * from {@link RescheduleService}, which owns single-session changes. Keeping the joins here means
 * neither of those has to grow a display concern.
 */
@Service
public class ScheduleFeedService {

    private final ClassInstanceRepository classInstanceRepository;
    private final BatchRepository batchRepository;
    private final BatchTrainerRepository batchTrainerRepository;
    private final BatchMemberRepository batchMemberRepository;
    private final CourseRepository courseRepository;
    private final AcademyMembershipRepository membershipRepository;
    private final UserRepository userRepository;
    private final AttendanceRepository attendanceRepository;
    private final CourseFeatureGuard courseFeatureGuard;

    public ScheduleFeedService(ClassInstanceRepository classInstanceRepository,
                                BatchRepository batchRepository,
                                BatchTrainerRepository batchTrainerRepository,
                                BatchMemberRepository batchMemberRepository,
                                CourseRepository courseRepository,
                                AcademyMembershipRepository membershipRepository,
                                UserRepository userRepository,
                                AttendanceRepository attendanceRepository,
                                CourseFeatureGuard courseFeatureGuard) {
        this.classInstanceRepository = classInstanceRepository;
        this.batchRepository = batchRepository;
        this.batchTrainerRepository = batchTrainerRepository;
        this.batchMemberRepository = batchMemberRepository;
        this.courseRepository = courseRepository;
        this.membershipRepository = membershipRepository;
        this.userRepository = userRepository;
        this.attendanceRepository = attendanceRepository;
        this.courseFeatureGuard = courseFeatureGuard;
    }

    /**
     * Every class between {@code from} and {@code to} inclusive, ordered by date then start time.
     *
     * @param courseId optional filter - null means every course in the academy.
     */
    @Transactional(readOnly = true)
    public List<ScheduleEntryResponse> feed(LocalDate from, LocalDate to, UUID courseId) {
        // A Trainer sees only the courses they hold RESCHEDULE on. Without this the feed is
        // academy-wide for everyone, so a trainer granted one course would still be shown every
        // other course's classes - and offered the kebab actions on them.
        var visible = courseFeatureGuard.visibleCourseIds(FeatureKey.RESCHEDULE);

        Map<UUID, Course> coursesById = courseRepository
                .findByAcademyIdOrderByNameAsc(TenantContext.currentAcademyId()).stream()
                .filter(c -> visible.isEmpty() || visible.get().contains(c.getId()))
                .filter(c -> courseId == null || c.getId().equals(courseId))
                .collect(Collectors.toMap(Course::getId, c -> c));
        if (coursesById.isEmpty()) {
            return List.of();
        }

        // An inactive batch's classes are excluded rather than greyed out: deactivating a batch
        // means it has stopped running, and leaving its sessions on the feed would have people
        // turning up to them.
        List<Batch> batches = batchRepository.findByCourseIdIn(coursesById.keySet()).stream()
                .filter(b -> b.getStatus() == BatchStatus.ACTIVE)
                .toList();
        if (batches.isEmpty()) {
            return List.of();
        }
        Map<UUID, Batch> batchesById = batches.stream()
                .collect(Collectors.toMap(Batch::getId, b -> b));

        List<ClassInstance> instances =
                classInstanceRepository.findByBatchIdInAndDateBetween(batchesById.keySet(), from, to);

        Map<UUID, List<UUID>> trainerIdsByBatch = new HashMap<>();
        for (BatchTrainer link : batchTrainerRepository.findByBatchIdIn(batchesById.keySet())) {
            trainerIdsByBatch.computeIfAbsent(link.getBatchId(), k -> new ArrayList<>())
                    .add(link.getTrainerMembershipId());
        }

        // One name lookup covering both the batches' regular trainers and any substitutes.
        Set<UUID> everyMembershipId = new java.util.HashSet<>();
        trainerIdsByBatch.values().forEach(everyMembershipId::addAll);
        instances.stream().map(ClassInstance::getSubstituteTrainerMembershipId)
                .filter(Objects::nonNull).forEach(everyMembershipId::add);
        Map<UUID, String> namesByMembership = resolveNames(everyMembershipId);

        // A reschedule's two halves reference each other, and the partner can sit outside the
        // requested window - so dates are resolved from the full set for these ids, not just the
        // page being rendered. Without this, "moved to 3 Oct" renders as "moved to (unknown)"
        // whenever the window ends on 30 Sep.
        Map<UUID, ClassInstance> partnerLookup = resolvePartners(instances);

        // "Has anyone marked this class?" for every instance at once. A per-class query here is
        // the difference between one round trip and thirty on a month view.
        Set<UUID> markedInstanceIds = instances.isEmpty()
                ? Set.of()
                : attendanceRepository
                        .findByClassInstanceIdIn(instances.stream().map(ClassInstance::getId).toList())
                        .stream().map(a -> a.getClassInstanceId()).collect(Collectors.toSet());

        Map<UUID, Integer> rosterSizes = new HashMap<>();
        for (BatchMember member : batchMemberRepository.findByBatchIdIn(batchesById.keySet())) {
            rosterSizes.merge(member.getBatchId(), 1, Integer::sum);
        }

        List<ScheduleEntryResponse> rows = new ArrayList<>();
        for (ClassInstance instance : instances) {
            Batch batch = batchesById.get(instance.getBatchId());
            if (batch == null) {
                continue;
            }
            Course course = coursesById.get(batch.getCourseId());
            if (course == null) {
                continue;
            }
            rows.add(toRow(instance, batch, course, trainerIdsByBatch, namesByMembership, partnerLookup,
                    markedInstanceIds.contains(instance.getId()),
                    rosterSizes.getOrDefault(batch.getId(), 0)));
        }

        rows.sort(Comparator.comparing(ScheduleEntryResponse::date)
                .thenComparing(ScheduleEntryResponse::startTime));
        return rows;
    }

    private ScheduleEntryResponse toRow(ClassInstance instance, Batch batch, Course course,
                                         Map<UUID, List<UUID>> trainerIdsByBatch,
                                         Map<UUID, String> namesByMembership,
                                         Map<UUID, ClassInstance> partnerLookup,
                                         boolean attendanceMarked,
                                         int studentCount) {
        List<ScheduleEntryResponse.PersonRef> regulars =
                trainerIdsByBatch.getOrDefault(batch.getId(), List.of()).stream()
                        .map(id -> new ScheduleEntryResponse.PersonRef(id, namesByMembership.get(id)))
                        .filter(p -> p.name() != null)
                        .sorted(Comparator.comparing(ScheduleEntryResponse.PersonRef::name))
                        .toList();

        UUID substituteId = instance.getSubstituteTrainerMembershipId();
        boolean swapped = substituteId != null && instance.getStatus() == ClassInstanceStatus.SCHEDULED;

        ScheduleEntryStatus status = switch (instance.getStatus()) {
            case HELD -> ScheduleEntryStatus.HELD;
            case CANCELLED -> ScheduleEntryStatus.CANCELLED;
            case RESCHEDULED_CANCELLED -> ScheduleEntryStatus.MOVED_OUT;
            case SCHEDULED -> swapped
                    ? ScheduleEntryStatus.SWAPPED
                    // originalInstanceId is only set on the replacement a reschedule created, so
                    // its presence is what makes this the "landed here" half.
                    : instance.getOriginalInstanceId() != null
                            ? ScheduleEntryStatus.MOVED_IN
                            : ScheduleEntryStatus.SCHEDULED;
        };

        List<ScheduleEntryResponse.PersonRef> teaching = swapped
                ? List.of(new ScheduleEntryResponse.PersonRef(
                        substituteId, namesByMembership.get(substituteId)))
                : regulars;

        LocalDate movedFrom = null;
        LocalDate movedTo = null;
        if (status == ScheduleEntryStatus.MOVED_IN) {
            ClassInstance origin = partnerLookup.get(instance.getOriginalInstanceId());
            movedFrom = origin == null ? null : origin.getDate();
        } else if (status == ScheduleEntryStatus.MOVED_OUT) {
            ClassInstance replacement = partnerLookup.get(instance.getId());
            movedTo = replacement == null ? null : replacement.getDate();
        }

        String reason = switch (status) {
            case CANCELLED -> instance.getCancellationReason();
            case SWAPPED -> instance.getSubstitutionReason();
            case MOVED_IN, MOVED_OUT -> instance.getRescheduleReason();
            default -> null;
        };

        return new ScheduleEntryResponse(
                instance.getId(), instance.getDate(), instance.getStartTime(), instance.getEndTime(),
                status,
                batch.getId(), batch.getName(), batch.getBatchType(),
                course.getId(), course.getName(), course.getCategory(), course.getIconKey(),
                teaching, swapped ? regulars : List.of(),
                reason, movedTo, movedFrom, attendanceMarked, studentCount);
    }

    /**
     * Indexes the other half of every reschedule visible in this window, keyed both by the
     * origin's id (so a MOVED_OUT row can find its replacement) and by the replacement's own id
     * where needed.
     */
    private Map<UUID, ClassInstance> resolvePartners(List<ClassInstance> instances) {
        Set<UUID> wanted = instances.stream()
                .map(ClassInstance::getOriginalInstanceId)
                .filter(Objects::nonNull)
                .collect(Collectors.toCollection(java.util.HashSet::new));

        Map<UUID, ClassInstance> byId = new HashMap<>();
        // Replacements already in this window index themselves under the origin they replaced,
        // which is the direction a MOVED_OUT row needs.
        for (ClassInstance instance : instances) {
            byId.put(instance.getId(), instance);
            if (instance.getOriginalInstanceId() != null) {
                byId.put(instance.getOriginalInstanceId(), instance);
            }
        }

        // Origins that fall outside the window still have to be fetched, or a MOVED_IN row can't
        // say where it came from.
        Set<UUID> missing = wanted.stream().filter(id -> !byId.containsKey(id))
                .collect(Collectors.toSet());
        if (!missing.isEmpty()) {
            for (ClassInstance origin : classInstanceRepository.findAllById(missing)) {
                byId.put(origin.getId(), origin);
            }
        }

        // The reverse direction for out-of-window replacements: an origin inside the window whose
        // replacement is not. Resolved by scanning that batch's instances rather than adding an
        // index, since it only affects rows that were actually moved.
        List<ClassInstance> movedOut = instances.stream()
                .filter(i -> i.getStatus() == ClassInstanceStatus.RESCHEDULED_CANCELLED)
                .filter(i -> !byId.containsKey(i.getId()) || byId.get(i.getId()) == i)
                .toList();
        for (ClassInstance origin : movedOut) {
            classInstanceRepository.findByBatchId(origin.getBatchId()).stream()
                    .filter(candidate -> origin.getId().equals(candidate.getOriginalInstanceId()))
                    .findFirst()
                    .ifPresent(replacement -> byId.put(origin.getId(), replacement));
        }
        return byId;
    }

    private Map<UUID, String> resolveNames(Set<UUID> membershipIds) {
        if (membershipIds.isEmpty()) {
            return Map.of();
        }
        List<AcademyMembership> memberships = membershipRepository.findAllById(membershipIds);
        Map<UUID, User> usersById = userRepository.findAllById(
                memberships.stream().map(AcademyMembership::getUserId).collect(Collectors.toSet())
        ).stream().collect(Collectors.toMap(User::getId, u -> u));

        Map<UUID, String> result = new HashMap<>();
        for (AcademyMembership membership : memberships) {
            User user = usersById.get(membership.getUserId());
            if (user != null) {
                result.put(membership.getId(), user.getFullName());
            }
        }
        return result;
    }
}
