package com.nest.app.curriculum.service;

import com.nest.app.curriculum.dto.StudyMaterialResponse;
import com.nest.app.curriculum.entity.Course;
import com.nest.app.curriculum.entity.MaterialTarget;
import com.nest.app.curriculum.entity.StudyMaterial;
import com.nest.app.curriculum.entity.StudyMaterialPermission;
import com.nest.app.curriculum.entity.StudyMaterialStudent;
import com.nest.app.curriculum.entity.StudyMaterialType;
import com.nest.app.curriculum.entity.StudyMaterialVisibility;
import com.nest.app.curriculum.repository.CourseRepository;
import com.nest.app.curriculum.repository.MaterialPlaylistEntryRepository;
import com.nest.app.curriculum.repository.StudyMaterialRepository;
import com.nest.app.curriculum.repository.StudyMaterialStudentRepository;
import com.nest.app.enrolment.entity.Batch;
import com.nest.app.enrolment.entity.BatchMember;
import com.nest.app.enrolment.entity.BatchType;
import com.nest.app.enrolment.repository.BatchMemberRepository;
import com.nest.app.enrolment.repository.BatchRepository;
import com.nest.app.enrolment.repository.BatchTrainerRepository;
import com.nest.app.identity.entity.CourseMap;
import com.nest.app.identity.repository.CourseMapRepository;
import com.nest.app.identity.repository.UserRepository;
import com.nest.app.identity.service.CourseFeatureGuard;
import com.nest.app.storage.FileStorageService;
import com.nest.common.exception.BadRequestException;
import com.nest.common.exception.ForbiddenException;
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
import org.springframework.mock.web.MockMultipartFile;

import java.time.Instant;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * Study material is shared with an audience of courses and/or batches. Pins who may share to what, and
 * who may open a file: the heart of "a Basic trainer must not reshape or open an Advanced-only file".
 */
@ExtendWith(MockitoExtension.class)
class StudyMaterialServiceTest {

    @Mock private StudyMaterialRepository studyMaterialRepository;
    @Mock private BatchRepository batchRepository;
    @Mock private BatchMemberRepository batchMemberRepository;
    @Mock private BatchTrainerRepository batchTrainerRepository;
    @Mock private CourseRepository courseRepository;
    @Mock private CourseMapRepository courseMapRepository;
    @Mock private UserRepository userRepository;
    @Mock private FileStorageService fileStorageService;
    @Mock private CourseFeatureGuard courseFeatureGuard;
    @Mock private StudyMaterialStudentRepository studyMaterialStudentRepository;
    @Mock private MaterialPlaylistEntryRepository playlistEntryRepository;

    private StudyMaterialService service;

    private final UUID academyId = UUID.randomUUID();
    private final UUID me = UUID.randomUUID();
    private final UUID basic = UUID.randomUUID();
    private final UUID advanced = UUID.randomUUID();

    @BeforeEach
    void setUp() {
        service = new StudyMaterialService(studyMaterialRepository, batchRepository, batchMemberRepository,
                batchTrainerRepository, courseRepository, courseMapRepository, userRepository, fileStorageService,
                courseFeatureGuard, studyMaterialStudentRepository, playlistEntryRepository);
        actingAs(Role.STUDENT);
        lenient().when(courseRepository.findAllById(any())).thenAnswer(inv -> {
            java.util.List<Course> found = new java.util.ArrayList<>();
            for (Object id : (Iterable<?>) inv.getArgument(0)) {
                found.add(Course.builder().id((UUID) id).academyId(academyId).name("Course").build());
            }
            return found;
        });
        lenient().when(studyMaterialRepository.save(any(StudyMaterial.class))).thenAnswer(inv -> {
            StudyMaterial m = inv.getArgument(0);
            if (m.getId() == null) {
                m.setId(UUID.randomUUID());
            }
            return m;
        });
        lenient().when(userRepository.findAllById(any())).thenReturn(List.of());
        lenient().when(studyMaterialStudentRepository.findByMaterialIdIn(any())).thenReturn(List.of());
    }

    @AfterEach
    void tearDown() {
        TenantContext.clear();
    }

    private void actingAs(Role role) {
        MembershipClaim claim = new MembershipClaim(me, academyId, "Natyalaya", role, Set.of(), Set.of());
        TenantContext.set(new NestPrincipal(UUID.randomUUID(), "actor", role, List.of(claim), me));
    }

    private void enrolledIn(UUID... courses) {
        lenient().when(courseMapRepository.findByMembershipId(me)).thenReturn(java.util.Arrays.stream(courses)
                .map(c -> CourseMap.builder().membershipId(me).courseId(c).build()).toList());
    }

    private StudyMaterial file(StudyMaterialVisibility visibility, MaterialTarget... targets) {
        return StudyMaterial.builder().id(UUID.randomUUID()).title("Chart").url("/u").fileName("c.pdf")
                .fileType(StudyMaterialType.NOTES).permission(StudyMaterialPermission.DOWNLOADABLE)
                .visibility(visibility).uploadedBy(UUID.randomUUID()).uploadedAt(Instant.now())
                .targets(new LinkedHashSet<>(List.of(targets))).build();
    }

    private Batch batchOf(UUID... courses) {
        Batch b = Batch.builder().id(UUID.randomUUID()).name("Saturday").batchType(BatchType.REGULAR).build();
        b.setCourses(List.of(courses));
        return b;
    }

    // ---------------------------------------------------------------- who may open a file

    @Test
    void aStudentEnrolledInATargetedCourseOpensTheFileEvenWithoutABatch() {
        StudyMaterial f = file(StudyMaterialVisibility.ALL, MaterialTarget.course(advanced));
        when(studyMaterialRepository.findAllById(any())).thenReturn(List.of(f));
        enrolledIn(advanced);

        assertThat(service.byIds(List.of(f.getId()))).hasSize(1);
    }

    @Test
    void aStudentOfAnotherCourseDoesNotSeeIt() {
        StudyMaterial f = file(StudyMaterialVisibility.ALL, MaterialTarget.course(advanced));
        when(studyMaterialRepository.findAllById(any())).thenReturn(List.of(f));
        enrolledIn(basic);

        assertThat(service.byIds(List.of(f.getId()))).isEmpty();
    }

    @Test
    void aBatchTargetReachesThatBatchsMembersOnly() {
        Batch saturday = batchOf(basic, advanced);
        StudyMaterial f = file(StudyMaterialVisibility.ALL, MaterialTarget.batch(saturday.getId()));
        when(studyMaterialRepository.findAllById(any())).thenReturn(List.of(f));
        when(batchRepository.findAllById(any())).thenReturn(List.of(saturday));
        when(batchMemberRepository.findByMembershipId(me)).thenReturn(List.of(
                BatchMember.builder().batchId(saturday.getId()).membershipId(me).build()));

        assertThat(service.byIds(List.of(f.getId()))).hasSize(1);
    }

    @Test
    void aFileNarrowedToChosenStudentsIsHiddenFromTheOthers() {
        StudyMaterial f = file(StudyMaterialVisibility.SELECTED, MaterialTarget.course(advanced));
        when(studyMaterialRepository.findAllById(any())).thenReturn(List.of(f));
        enrolledIn(advanced);

        // Enrolled, but not among the students it was narrowed to.
        assertThat(service.byIds(List.of(f.getId()))).isEmpty();

        when(studyMaterialStudentRepository.findByMaterialIdIn(any())).thenReturn(List.of(
                StudyMaterialStudent.builder().materialId(f.getId()).membershipId(me).build()));
        assertThat(service.byIds(List.of(f.getId()))).hasSize(1);
    }

    @Test
    void aTrainerHoldingOneOfTwoTargetedCoursesOpensButCannotManageTheFile() {
        actingAs(Role.TRAINER);
        StudyMaterial f = file(StudyMaterialVisibility.ALL, MaterialTarget.course(basic), MaterialTarget.course(advanced));
        when(studyMaterialRepository.findAllById(any())).thenReturn(List.of(f));
        when(courseFeatureGuard.hasCourseFeature(basic, FeatureKey.SYLLABUS_EDIT)).thenReturn(true);

        List<StudyMaterialResponse> seen = service.byIds(List.of(f.getId()));

        assertThat(seen).hasSize(1);
        assertThat(seen.get(0).canManage()).isFalse();
    }

    @Test
    void aTrainerWithNoneOfTheTargetedCoursesDoesNotSeeTheFile() {
        actingAs(Role.TRAINER);
        StudyMaterial f = file(StudyMaterialVisibility.ALL, MaterialTarget.course(advanced));
        when(studyMaterialRepository.findAllById(any())).thenReturn(List.of(f));

        assertThat(service.byIds(List.of(f.getId()))).isEmpty();
    }

    @Test
    void aTrainerLimitedToSomeBatchesOfACourseIsNotStaffForTheWholeCourse() {
        actingAs(Role.TRAINER);
        StudyMaterial f = file(StudyMaterialVisibility.ALL, MaterialTarget.course(basic));
        when(studyMaterialRepository.findAllById(any())).thenReturn(List.of(f));
        when(courseFeatureGuard.hasCourseFeature(basic, FeatureKey.SYLLABUS_EDIT)).thenReturn(true);
        when(courseFeatureGuard.batchScope(basic)).thenReturn(Optional.of(Set.of(UUID.randomUUID())));

        assertThat(service.byIds(List.of(f.getId()))).isEmpty();
    }

    // ---------------------------------------------------------------- sharing

    private MockMultipartFile pdf() {
        return new MockMultipartFile("file", "chart.pdf", "application/pdf", new byte[] {1, 2, 3});
    }

    @Test
    void aFileCanBeSharedWithAWholeCourseThatHasNoBatches() {
        when(fileStorageService.store(any(), any(), any(), org.mockito.ArgumentMatchers.anyLong())).thenReturn("/files/c.pdf");
        when(courseFeatureGuard.hasCourseFeature(advanced, FeatureKey.SYLLABUS_EDIT)).thenReturn(true);

        StudyMaterialResponse response = service.upload(Set.of(), Set.of(advanced), pdf(), null, null, null, null, null);

        assertThat(response.batchId()).isNull();
        assertThat(response.targets()).extracting(StudyMaterialResponse.Target::id).containsExactly(advanced);
        assertThat(response.canManage()).isTrue();
    }

    @Test
    void sharingWithABatchNeedsTheGrantOnEveryCourseItSpans() {
        Batch saturday = batchOf(basic, advanced);
        when(batchRepository.findAllById(any())).thenReturn(List.of(saturday));
        when(courseFeatureGuard.hasCourseFeature(basic, FeatureKey.SYLLABUS_EDIT)).thenReturn(true);
        when(courseFeatureGuard.hasCourseFeature(advanced, FeatureKey.SYLLABUS_EDIT)).thenReturn(false);

        assertThatThrownBy(() -> service.upload(Set.of(saturday.getId()), Set.of(), pdf(), null, null, null, null, null))
                .isInstanceOf(ForbiddenException.class);
        verify(studyMaterialRepository, never()).save(any());
    }

    @Test
    void sharingWithNobodyIsRefused() {
        assertThatThrownBy(() -> service.upload(Set.of(), Set.of(), pdf(), null, null, null, null, null))
                .isInstanceOf(BadRequestException.class).hasMessageContaining("at least one course or batch");
    }

    @Test
    void aTrainerLimitedToSomeBatchesCannotShareWithTheWholeCourse() {
        actingAs(Role.TRAINER);
        when(courseFeatureGuard.hasCourseFeature(basic, FeatureKey.SYLLABUS_EDIT)).thenReturn(true);
        when(courseFeatureGuard.batchScope(basic)).thenReturn(Optional.of(Set.of(UUID.randomUUID())));

        assertThatThrownBy(() -> service.upload(Set.of(), Set.of(basic), pdf(), null, null, null, null, null))
                .isInstanceOf(ForbiddenException.class).hasMessageContaining("only some batches");
    }

    @Test
    void aCourseFromAnotherAcademyCannotBeSharedWith() {
        UUID foreign = UUID.randomUUID();
        lenient().doReturn(List.of(Course.builder().id(foreign).academyId(UUID.randomUUID()).name("X").build()))
                .when(courseRepository).findAllById(any());

        assertThatThrownBy(() -> service.upload(Set.of(), Set.of(foreign), pdf(), null, null, null, null, null))
                .isInstanceOf(com.nest.common.exception.ResourceNotFoundException.class);
    }

    @Test
    void anAudienceOfChosenStudentsOnlyKeepsThoseWhoAreActuallyInIt() {
        when(fileStorageService.store(any(), any(), any(), org.mockito.ArgumentMatchers.anyLong())).thenReturn("/files/c.pdf");
        when(courseFeatureGuard.hasCourseFeature(advanced, FeatureKey.SYLLABUS_EDIT)).thenReturn(true);
        UUID inCourse = UUID.randomUUID();
        UUID stranger = UUID.randomUUID();
        when(courseMapRepository.findByCourseId(advanced)).thenReturn(List.of(
                CourseMap.builder().membershipId(inCourse).courseId(advanced).build()));

        service.upload(Set.of(), Set.of(advanced), pdf(), null, null, null,
                StudyMaterialVisibility.SELECTED, Set.of(inCourse, stranger));

        org.mockito.ArgumentCaptor<StudyMaterialStudent> saved = org.mockito.ArgumentCaptor.forClass(StudyMaterialStudent.class);
        verify(studyMaterialStudentRepository).save(saved.capture());
        assertThat(saved.getValue().getMembershipId()).isEqualTo(inCourse);
    }

    // ---------------------------------------------------------------- a batch going away

    @Test
    void deletingABatchRemovesAFileWhoseOnlyAudienceItWasAndKeepsTheRest() {
        UUID batchId = UUID.randomUUID();
        StudyMaterial onlyThisBatch = file(StudyMaterialVisibility.ALL, MaterialTarget.batch(batchId));
        onlyThisBatch.setBatchId(batchId);
        StudyMaterial alsoACourse = file(StudyMaterialVisibility.ALL, MaterialTarget.batch(batchId), MaterialTarget.course(advanced));
        alsoACourse.setBatchId(batchId);
        when(studyMaterialRepository.findForTargets(any(), any())).thenReturn(List.of(onlyThisBatch, alsoACourse));

        service.detachBatch(batchId);

        verify(studyMaterialRepository).delete(onlyThisBatch);
        verify(studyMaterialRepository, never()).delete(alsoACourse);
        assertThat(alsoACourse.getTargets()).containsExactly(MaterialTarget.course(advanced));
        assertThat(alsoACourse.getBatchId()).isNull();
    }
}
