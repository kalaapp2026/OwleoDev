package com.nest.app.curriculum.service;

import com.nest.app.curriculum.entity.SyllabusUnit;
import com.nest.app.curriculum.repository.MaterialAttachmentRepository;
import com.nest.app.curriculum.repository.SyllabusUnitRepository;
import com.nest.app.curriculum.repository.TrackRepository;
import com.nest.app.enrolment.entity.Batch;
import com.nest.app.enrolment.entity.BatchMember;
import com.nest.app.enrolment.entity.BatchType;
import com.nest.app.enrolment.repository.BatchMemberRepository;
import com.nest.app.enrolment.repository.BatchRepository;
import com.nest.app.identity.entity.AcademyMembership;
import com.nest.app.identity.entity.CourseMap;
import com.nest.app.identity.repository.AcademyMembershipRepository;
import com.nest.app.identity.repository.CourseMapRepository;
import com.nest.app.storage.FileStorageService;
import com.nest.common.exception.ForbiddenException;
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

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.when;

/** Covers the material-visibility scoping this feature is built around: course-wide material
 * needs course enrolment, batch-targeted material needs batch membership (or, for a Trainer,
 * teaching that batch) - never just any authenticated caller. */
@ExtendWith(MockitoExtension.class)
class SyllabusServiceTest {

    @Mock
    private SyllabusUnitRepository syllabusUnitRepository;
    @Mock
    private TrackRepository trackRepository;
    @Mock
    private MaterialAttachmentRepository materialAttachmentRepository;
    @Mock
    private CourseMapRepository courseMapRepository;
    @Mock
    private AcademyMembershipRepository membershipRepository;
    @Mock
    private BatchRepository batchRepository;
    @Mock
    private BatchMemberRepository batchMemberRepository;
    @Mock
    private FileStorageService fileStorageService;

    private SyllabusService syllabusService;

    private final UUID academyId = UUID.randomUUID();
    private final UUID courseId = UUID.randomUUID();
    private final UUID membershipId = UUID.randomUUID();

    @BeforeEach
    void setUp() {
        syllabusService = new SyllabusService(syllabusUnitRepository, trackRepository, materialAttachmentRepository,
                courseMapRepository, membershipRepository, batchRepository, batchMemberRepository, fileStorageService);

        MembershipClaim claim = new MembershipClaim(UUID.randomUUID(), academyId, "Natyalaya", Role.ACADEMY_ADMIN, Set.of(), Set.of());
        TenantContext.set(new NestPrincipal(UUID.randomUUID(), "meera", Role.ACADEMY_ADMIN, List.of(claim), claim.membershipId()));
    }

    @AfterEach
    void tearDown() {
        TenantContext.clear();
    }

    @Test
    void courseWideMaterialIsVisibleToAnyoneEnrolledInTheCourse() {
        SyllabusUnit unit = SyllabusUnit.builder().id(UUID.randomUUID()).courseId(courseId).title("Intro").batchIds(Set.of()).build();
        when(syllabusUnitRepository.findByCourseIdOrderByOrderIndex(courseId)).thenReturn(List.of(unit));
        when(membershipRepository.findById(membershipId))
                .thenReturn(Optional.of(AcademyMembership.builder().id(membershipId).academyId(academyId).build()));
        when(courseMapRepository.findByMembershipIdAndCourseId(membershipId, courseId))
                .thenReturn(Optional.of(CourseMap.builder().membershipId(membershipId).courseId(courseId).build()));
        when(batchMemberRepository.findByMembershipId(membershipId)).thenReturn(List.of());
        when(batchRepository.findByTrainerMembershipId(membershipId)).thenReturn(List.of());

        var result = syllabusService.listForCourse(courseId, membershipId);

        assertThat(result).hasSize(1);
    }

    @Test
    void courseWideMaterialIsHiddenFromSomeoneNotEnrolledInTheCourse() {
        SyllabusUnit unit = SyllabusUnit.builder().id(UUID.randomUUID()).courseId(courseId).title("Intro").batchIds(Set.of()).build();
        when(syllabusUnitRepository.findByCourseIdOrderByOrderIndex(courseId)).thenReturn(List.of(unit));
        when(membershipRepository.findById(membershipId))
                .thenReturn(Optional.of(AcademyMembership.builder().id(membershipId).academyId(academyId).build()));
        when(courseMapRepository.findByMembershipIdAndCourseId(membershipId, courseId)).thenReturn(Optional.empty());
        when(batchMemberRepository.findByMembershipId(membershipId)).thenReturn(List.of());
        when(batchRepository.findByTrainerMembershipId(membershipId)).thenReturn(List.of());

        var result = syllabusService.listForCourse(courseId, membershipId);

        assertThat(result).isEmpty();
    }

    @Test
    void batchTargetedMaterialIsVisibleOnlyToThatBatchsStudentMembers() {
        UUID batchId = UUID.randomUUID();
        SyllabusUnit unit = SyllabusUnit.builder().id(UUID.randomUUID()).courseId(courseId).title("Advanced steps").batchIds(Set.of(batchId)).build();
        when(syllabusUnitRepository.findByCourseIdOrderByOrderIndex(courseId)).thenReturn(List.of(unit));
        when(membershipRepository.findById(membershipId))
                .thenReturn(Optional.of(AcademyMembership.builder().id(membershipId).academyId(academyId).build()));
        when(courseMapRepository.findByMembershipIdAndCourseId(membershipId, courseId)).thenReturn(Optional.empty());
        when(batchMemberRepository.findByMembershipId(membershipId))
                .thenReturn(List.of(BatchMember.builder().batchId(batchId).membershipId(membershipId).build()));
        when(batchRepository.findByTrainerMembershipId(membershipId)).thenReturn(List.of());

        var result = syllabusService.listForCourse(courseId, membershipId);

        assertThat(result).hasSize(1);
    }

    @Test
    void batchTargetedMaterialIsVisibleToTheBatchsTrainerEvenWithoutBeingAMember() {
        UUID batchId = UUID.randomUUID();
        SyllabusUnit unit = SyllabusUnit.builder().id(UUID.randomUUID()).courseId(courseId).title("Advanced steps").batchIds(Set.of(batchId)).build();
        when(syllabusUnitRepository.findByCourseIdOrderByOrderIndex(courseId)).thenReturn(List.of(unit));
        when(membershipRepository.findById(membershipId))
                .thenReturn(Optional.of(AcademyMembership.builder().id(membershipId).academyId(academyId).build()));
        when(courseMapRepository.findByMembershipIdAndCourseId(membershipId, courseId)).thenReturn(Optional.empty());
        when(batchMemberRepository.findByMembershipId(membershipId)).thenReturn(List.of());
        when(batchRepository.findByTrainerMembershipId(membershipId))
                .thenReturn(List.of(Batch.builder().id(batchId).courseId(courseId).batchType(BatchType.REGULAR).trainerMembershipId(membershipId).build()));

        var result = syllabusService.listForCourse(courseId, membershipId);

        assertThat(result).hasSize(1);
    }

    @Test
    void batchTargetedMaterialIsHiddenFromSomeoneInADifferentBatch() {
        UUID batchId = UUID.randomUUID();
        UUID otherBatchId = UUID.randomUUID();
        SyllabusUnit unit = SyllabusUnit.builder().id(UUID.randomUUID()).courseId(courseId).title("Advanced steps").batchIds(Set.of(batchId)).build();
        when(syllabusUnitRepository.findByCourseIdOrderByOrderIndex(courseId)).thenReturn(List.of(unit));
        when(membershipRepository.findById(membershipId))
                .thenReturn(Optional.of(AcademyMembership.builder().id(membershipId).academyId(academyId).build()));
        when(courseMapRepository.findByMembershipIdAndCourseId(membershipId, courseId))
                .thenReturn(Optional.of(CourseMap.builder().membershipId(membershipId).courseId(courseId).build()));
        when(batchMemberRepository.findByMembershipId(membershipId))
                .thenReturn(List.of(BatchMember.builder().batchId(otherBatchId).membershipId(membershipId).build()));
        when(batchRepository.findByTrainerMembershipId(membershipId)).thenReturn(List.of());

        var result = syllabusService.listForCourse(courseId, membershipId);

        assertThat(result).isEmpty();
    }

    @Test
    void unscopedListingReturnsEverythingRegardlessOfTargeting() {
        SyllabusUnit courseWide = SyllabusUnit.builder().id(UUID.randomUUID()).courseId(courseId).title("Intro").batchIds(Set.of()).build();
        SyllabusUnit batchOnly = SyllabusUnit.builder().id(UUID.randomUUID()).courseId(courseId).title("Advanced")
                .batchIds(Set.of(UUID.randomUUID())).build();
        when(syllabusUnitRepository.findByCourseIdOrderByOrderIndex(courseId)).thenReturn(List.of(courseWide, batchOnly));

        var result = syllabusService.listForCourse(courseId, null);

        assertThat(result).hasSize(2);
    }

    @Test
    void membershipFromAnotherAcademyIsRejected() {
        when(membershipRepository.findById(membershipId))
                .thenReturn(Optional.of(AcademyMembership.builder().id(membershipId).academyId(UUID.randomUUID()).build()));
        when(syllabusUnitRepository.findByCourseIdOrderByOrderIndex(courseId)).thenReturn(List.of());

        assertThatThrownBy(() -> syllabusService.listForCourse(courseId, membershipId)).isInstanceOf(ForbiddenException.class);
    }
}
