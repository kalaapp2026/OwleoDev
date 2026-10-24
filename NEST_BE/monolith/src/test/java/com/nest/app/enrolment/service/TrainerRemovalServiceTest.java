package com.nest.app.enrolment.service;

import com.nest.app.enrolment.entity.Batch;
import com.nest.app.enrolment.entity.BatchTrainer;
import com.nest.app.enrolment.repository.BatchRepository;
import com.nest.app.enrolment.repository.BatchTrainerRepository;
import com.nest.app.identity.entity.AcademyMembership;
import com.nest.app.identity.entity.CourseFeatureGrant;
import com.nest.app.identity.entity.CourseMap;
import com.nest.app.identity.entity.TrainerCourseBatch;
import com.nest.app.identity.repository.AcademyMembershipRepository;
import com.nest.app.identity.repository.CourseFeatureGrantRepository;
import com.nest.app.identity.repository.CourseMapRepository;
import com.nest.app.identity.repository.TrainerCourseBatchRepository;
import com.nest.app.identity.service.CourseFeatureGuard;
import com.nest.common.exception.ForbiddenException;
import com.nest.common.exception.ResourceNotFoundException;
import com.nest.common.security.FeatureKey;
import com.nest.common.security.MembershipClaim;
import com.nest.common.security.NestPrincipal;
import com.nest.common.security.Role;
import com.nest.common.security.TenantContext;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.List;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class TrainerRemovalServiceTest {

    @Mock private AcademyMembershipRepository membershipRepository;
    @Mock private CourseMapRepository courseMapRepository;
    @Mock private CourseFeatureGrantRepository grantRepository;
    @Mock private TrainerCourseBatchRepository scopingRepository;
    @Mock private BatchRepository batchRepository;
    @Mock private BatchTrainerRepository batchTrainerRepository;
    @Mock private CourseFeatureGuard guard;

    private TrainerRemovalService service;
    private final UUID academyId = UUID.randomUUID();
    private final UUID courseId = UUID.randomUUID();
    private final UUID otherCourseId = UUID.randomUUID();
    private final UUID trainerId = UUID.randomUUID();

    @BeforeEach
    void setUp() {
        service = new TrainerRemovalService(membershipRepository, courseMapRepository, grantRepository,
                scopingRepository, batchRepository, batchTrainerRepository, guard);
        UUID adminMembership = UUID.randomUUID();
        TenantContext.set(new NestPrincipal(UUID.randomUUID(), "meera", Role.ACADEMY_ADMIN,
                List.of(new MembershipClaim(adminMembership, academyId, "Natyalaya", Role.ACADEMY_ADMIN, Set.of(), Set.of())),
                adminMembership));
    }

    @AfterEach
    void tearDown() {
        TenantContext.clear();
    }

    private AcademyMembership trainer(UUID inAcademy, Role role) {
        return AcademyMembership.builder().id(trainerId).academyId(inAcademy).roleType(role).build();
    }

    @Test
    void removesThePlaceTheGrantsTheScopingAndTheBatchSeatsOnThatCourseOnly() {
        when(membershipRepository.findById(trainerId)).thenReturn(Optional.of(trainer(academyId, Role.TRAINER)));
        CourseMap map = CourseMap.builder().membershipId(trainerId).courseId(courseId).build();
        when(courseMapRepository.findByMembershipIdAndCourseId(trainerId, courseId)).thenReturn(Optional.of(map));
        CourseFeatureGrant here = CourseFeatureGrant.builder().membershipId(trainerId).courseId(courseId).featureKey("ATTENDANCE").build();
        CourseFeatureGrant elsewhere = CourseFeatureGrant.builder().membershipId(trainerId).courseId(otherCourseId).featureKey("ATTENDANCE").build();
        when(grantRepository.findByMembershipId(trainerId)).thenReturn(List.of(here, elsewhere));
        List<TrainerCourseBatch> scoping = List.of(new TrainerCourseBatch());
        when(scopingRepository.findByMembershipIdAndCourseId(trainerId, courseId)).thenReturn(scoping);

        UUID batchId = UUID.randomUUID();
        Batch batch = new Batch();
        batch.setId(batchId);
        batch.setTrainerMembershipId(trainerId);
        when(batchRepository.findByCourseId(courseId)).thenReturn(List.of(batch));
        BatchTrainer seat = new BatchTrainer(batchId, trainerId);
        BatchTrainer colleague = new BatchTrainer(batchId, UUID.randomUUID());
        when(batchTrainerRepository.findByBatchIdIn(List.of(batchId))).thenReturn(List.of(seat, colleague));

        service.removeFromCourse(courseId, trainerId);

        verify(guard).assertCourseFeature(courseId, FeatureKey.TRAINER_REGISTRATION);
        verify(courseMapRepository).delete(map);
        verify(grantRepository).deleteAll(List.of(here));
        verify(scopingRepository).deleteAll(scoping);
        assertNull(batch.getTrainerMembershipId());
        verify(batchTrainerRepository).deleteAll(List.of(seat));
    }

    @Test
    void aTrainerNotOnTheCourseIsNotFound() {
        when(membershipRepository.findById(trainerId)).thenReturn(Optional.of(trainer(academyId, Role.TRAINER)));
        when(courseMapRepository.findByMembershipIdAndCourseId(trainerId, courseId)).thenReturn(Optional.empty());

        assertThrows(ResourceNotFoundException.class, () -> service.removeFromCourse(courseId, trainerId));
        verify(courseMapRepository, never()).delete(any());
    }

    @Test
    void anotherAcademysTrainerIsRefused() {
        when(membershipRepository.findById(trainerId)).thenReturn(Optional.of(trainer(UUID.randomUUID(), Role.TRAINER)));
        assertThrows(ForbiddenException.class, () -> service.removeFromCourse(courseId, trainerId));
        verify(courseMapRepository, never()).delete(any());
    }

    @Test
    void aStudentIsNotRemovedThroughTheTrainerEndpoint() {
        when(membershipRepository.findById(trainerId)).thenReturn(Optional.of(trainer(academyId, Role.STUDENT)));
        assertThrows(ForbiddenException.class, () -> service.removeFromCourse(courseId, trainerId));
    }
}
