package com.nest.app.calendar.service;

import com.nest.app.calendar.dto.CalendarClassResponse;
import com.nest.app.curriculum.entity.Course;
import com.nest.app.curriculum.repository.CourseRepository;
import com.nest.app.enrolment.entity.Batch;
import com.nest.app.enrolment.entity.BatchMember;
import com.nest.app.enrolment.repository.BatchMemberRepository;
import com.nest.app.enrolment.repository.BatchRepository;
import com.nest.app.identity.entity.AcademyMembership;
import com.nest.app.identity.entity.MembershipStatus;
import com.nest.app.identity.repository.AcademyMembershipRepository;
import com.nest.app.scheduling.entity.ClassInstance;
import com.nest.app.scheduling.repository.ClassInstanceRepository;
import com.nest.common.security.TenantContext;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;

/**
 * PRD 7.5's merged multi-academy calendar - unlike every other ERP endpoint, this one is
 * deliberately NOT scoped to just {@link TenantContext#currentAcademyId()}. It walks every ACTIVE
 * membership the caller holds (a person may be a Student at one academy and a Trainer/Admin at
 * another) and unions each academy's classes, tagged with which membership they came from so the
 * frontend can colour-code by academy.
 */
@Service
public class CalendarService {

    private final AcademyMembershipRepository membershipRepository;
    private final BatchRepository batchRepository;
    private final BatchMemberRepository batchMemberRepository;
    private final CourseRepository courseRepository;
    private final ClassInstanceRepository classInstanceRepository;

    public CalendarService(AcademyMembershipRepository membershipRepository, BatchRepository batchRepository,
                            BatchMemberRepository batchMemberRepository, CourseRepository courseRepository,
                            ClassInstanceRepository classInstanceRepository) {
        this.membershipRepository = membershipRepository;
        this.batchRepository = batchRepository;
        this.batchMemberRepository = batchMemberRepository;
        this.courseRepository = courseRepository;
        this.classInstanceRepository = classInstanceRepository;
    }

    @Transactional(readOnly = true)
    public List<CalendarClassResponse> classesForCaller(LocalDate from, LocalDate to) {
        UUID userId = TenantContext.currentUserId();
        List<AcademyMembership> memberships = membershipRepository.findByUserIdAndStatus(userId, MembershipStatus.ACTIVE);

        List<CalendarClassResponse> result = new ArrayList<>();
        for (AcademyMembership membership : memberships) {
            result.addAll(classesForMembership(membership, from, to));
        }
        return result;
    }

    private List<CalendarClassResponse> classesForMembership(AcademyMembership membership, LocalDate from, LocalDate to) {
        Set<UUID> batchIds = switch (membership.getRoleType()) {
            case ACADEMY_ADMIN -> batchIdsForAcademy(membership.getAcademyId());
            case TRAINER -> batchRepository.findByTrainerMembershipId(membership.getId()).stream()
                    .map(Batch::getId).collect(Collectors.toSet());
            case STUDENT -> batchMemberRepository.findByMembershipId(membership.getId()).stream()
                    .map(BatchMember::getBatchId).collect(Collectors.toSet());
            // Super Admin/Artist/Guest memberships don't exist in academy_memberships (PRD 2.4) -
            // this switch never actually sees those roles, kept exhaustive for compiler safety.
            default -> Set.<UUID>of();
        };
        if (batchIds.isEmpty()) {
            return List.of();
        }

        List<Batch> batches = batchRepository.findAllById(batchIds);
        Map<UUID, Batch> batchesById = batches.stream().collect(Collectors.toMap(Batch::getId, b -> b));
        Map<UUID, Course> coursesById = courseRepository.findAllById(
                batches.stream().map(Batch::getCourseId).collect(Collectors.toSet())
        ).stream().collect(Collectors.toMap(Course::getId, c -> c));

        List<ClassInstance> instances = classInstanceRepository.findByBatchIdInAndDateBetween(batchIds, from, to);

        List<CalendarClassResponse> result = new ArrayList<>();
        for (ClassInstance ci : instances) {
            Batch batch = batchesById.get(ci.getBatchId());
            if (batch == null) {
                continue;
            }
            Course course = coursesById.get(batch.getCourseId());
            result.add(new CalendarClassResponse(
                    ci.getId(), ci.getDate(), ci.getStartTime(), ci.getEndTime(), ci.getStatus(),
                    batch.getId(), batch.getName(),
                    course != null ? course.getId() : null, course != null ? course.getName() : null,
                    membership.getAcademyId(), membership.getAcademyName(),
                    membership.getId()
            ));
        }
        return result;
    }

    private Set<UUID> batchIdsForAcademy(UUID academyId) {
        Set<UUID> courseIds = courseRepository.findByAcademyIdOrderByNameAsc(academyId).stream()
                .map(Course::getId).collect(Collectors.toSet());
        if (courseIds.isEmpty()) {
            return Set.of();
        }
        return batchRepository.findByCourseIdIn(courseIds).stream().map(Batch::getId).collect(Collectors.toSet());
    }
}
