package com.nest.app.enrolment.service;

import com.nest.app.enrolment.entity.Batch;
import com.nest.app.enrolment.entity.BatchTrainer;
import com.nest.app.enrolment.repository.BatchRepository;
import com.nest.app.enrolment.repository.BatchTrainerRepository;
import com.nest.app.identity.entity.AcademyMembership;
import com.nest.app.identity.entity.CourseMap;
import com.nest.app.identity.repository.AcademyMembershipRepository;
import com.nest.app.identity.repository.CourseFeatureGrantRepository;
import com.nest.app.identity.repository.CourseMapRepository;
import com.nest.app.identity.repository.TrainerCourseBatchRepository;
import com.nest.app.identity.service.CourseFeatureGuard;
import com.nest.common.audit.Auditable;
import com.nest.common.exception.ForbiddenException;
import com.nest.common.exception.ResourceNotFoundException;
import com.nest.common.security.FeatureKey;
import com.nest.common.security.Role;
import com.nest.common.security.TenantContext;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.UUID;

/**
 * Takes a trainer off one course for good. Unlike deactivating them (which keeps the row so the
 * trainer can be switched back on, and leaves them on the roster, greyed), this drops their place on
 * the course, the features they held on it, their batch scoping and their seat on its batches.
 *
 * <p>Their NEST account, their other courses and the history they taught (past classes, attendance)
 * are left alone.
 */
@Service
public class TrainerRemovalService {

    private final AcademyMembershipRepository membershipRepository;
    private final CourseMapRepository courseMapRepository;
    private final CourseFeatureGrantRepository courseFeatureGrantRepository;
    private final TrainerCourseBatchRepository trainerCourseBatchRepository;
    private final BatchRepository batchRepository;
    private final BatchTrainerRepository batchTrainerRepository;
    private final CourseFeatureGuard courseFeatureGuard;

    public TrainerRemovalService(AcademyMembershipRepository membershipRepository,
                                 CourseMapRepository courseMapRepository,
                                 CourseFeatureGrantRepository courseFeatureGrantRepository,
                                 TrainerCourseBatchRepository trainerCourseBatchRepository,
                                 BatchRepository batchRepository,
                                 BatchTrainerRepository batchTrainerRepository,
                                 CourseFeatureGuard courseFeatureGuard) {
        this.membershipRepository = membershipRepository;
        this.courseMapRepository = courseMapRepository;
        this.courseFeatureGrantRepository = courseFeatureGrantRepository;
        this.trainerCourseBatchRepository = trainerCourseBatchRepository;
        this.batchRepository = batchRepository;
        this.batchTrainerRepository = batchTrainerRepository;
        this.courseFeatureGuard = courseFeatureGuard;
    }

    @Transactional
    @Auditable(action = "TRAINER_REMOVED_FROM_COURSE", entityType = "course_map")
    public void removeFromCourse(UUID courseId, UUID membershipId) {
        AcademyMembership membership = membershipRepository.findById(membershipId)
                .orElseThrow(() -> new ResourceNotFoundException("Trainer not found: " + membershipId));
        if (!membership.getAcademyId().equals(TenantContext.currentAcademyId()) || membership.getRoleType() != Role.TRAINER) {
            throw new ForbiddenException("That trainer does not belong to the active academy");
        }
        courseFeatureGuard.assertCourseFeature(courseId, FeatureKey.TRAINER_REGISTRATION);
        CourseMap courseMap = courseMapRepository.findByMembershipIdAndCourseId(membershipId, courseId)
                .orElseThrow(() -> new ResourceNotFoundException("That trainer is not on this course"));

        courseMapRepository.delete(courseMap);
        courseFeatureGrantRepository.deleteAll(courseFeatureGrantRepository.findByMembershipId(membershipId).stream()
                .filter(g -> g.getCourseId().equals(courseId)).toList());
        trainerCourseBatchRepository.deleteAll(trainerCourseBatchRepository.findByMembershipIdAndCourseId(membershipId, courseId));

        List<Batch> batches = batchRepository.findByCourseId(courseId);
        for (Batch batch : batches) {
            if (membershipId.equals(batch.getTrainerMembershipId())) {
                batch.setTrainerMembershipId(null);
                batchRepository.save(batch);
            }
        }
        List<BatchTrainer> seats = batchTrainerRepository.findByBatchIdIn(batches.stream().map(Batch::getId).toList()).stream()
                .filter(bt -> bt.getTrainerMembershipId().equals(membershipId)).toList();
        batchTrainerRepository.deleteAll(seats);
    }
}
