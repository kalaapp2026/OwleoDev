package com.nest.app.enrolment.service;

import com.nest.app.enrolment.entity.Batch;
import com.nest.app.enrolment.entity.BatchMember;
import com.nest.app.enrolment.entity.BatchType;
import com.nest.app.enrolment.repository.BatchMemberRepository;
import com.nest.app.enrolment.repository.BatchRepository;
import com.nest.app.identity.repository.AcademyMembershipRepository;
import com.nest.app.identity.repository.UserRepository;
import com.nest.app.scheduling.entity.ClassInstance;
import com.nest.app.scheduling.entity.ClassInstanceStatus;
import com.nest.app.scheduling.repository.ClassInstanceRepository;
import com.nest.app.scheduling.repository.ScheduleRepository;
import com.nest.common.exception.BadRequestException;
import com.nest.common.exception.ConflictException;
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

import java.util.List;
import java.util.Set;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/** Covers PRD 3.6: one Regular batch per course per student, unlimited Temporary batches. */
@ExtendWith(MockitoExtension.class)
class BatchServiceTest {

    @Mock
    private BatchRepository batchRepository;
    @Mock
    private BatchMemberRepository batchMemberRepository;
    @Mock
    private com.nest.app.enrolment.repository.BatchTrainerRepository batchTrainerRepository;
    @Mock
    private AcademyMembershipRepository membershipRepository;
    @Mock
    private UserRepository userRepository;
    @Mock
    private com.nest.app.curriculum.repository.CourseRepository courseRepository;
    @Mock
    private ScheduleRepository scheduleRepository;
    @Mock
    private ClassInstanceRepository classInstanceRepository;
    @Mock
    private com.nest.app.curriculum.service.StudyMaterialService studyMaterialService;
    @Mock
    private com.nest.app.identity.service.CourseFeatureGuard courseFeatureGuard;
    @Mock
    private com.nest.app.identity.repository.CourseMapRepository courseMapRepository;

    private BatchService batchService;

    private final UUID courseId = UUID.randomUUID();
    private final UUID membershipId = UUID.randomUUID();
    private final UUID academyId = UUID.randomUUID();

    @AfterEach
    void tearDown() {
        TenantContext.clear();
    }

    @BeforeEach
    void setUp() {
        UUID adminMembership = UUID.randomUUID();
        TenantContext.set(new NestPrincipal(UUID.randomUUID(), "admin", Role.ACADEMY_ADMIN,
                List.of(new MembershipClaim(adminMembership, academyId, "Natyalaya", Role.ACADEMY_ADMIN, Set.of(), Set.of())),
                adminMembership));
        // Every course id a request names exists, in the caller's academy.
        lenient().when(courseRepository.findAllById(any())).thenAnswer(inv -> {
            java.util.List<com.nest.app.curriculum.entity.Course> found = new java.util.ArrayList<>();
            for (Object id : (Iterable<?>) inv.getArgument(0)) {
                found.add(com.nest.app.curriculum.entity.Course.builder().id((UUID) id).academyId(academyId).name("Course").build());
            }
            return found;
        });
        lenient().when(courseMapRepository.findByMembershipIdIn(any())).thenReturn(List.of());
        batchService = new BatchService(batchRepository, batchMemberRepository, batchTrainerRepository,
                membershipRepository, userRepository, courseRepository,
                scheduleRepository, classInstanceRepository, studyMaterialService, courseFeatureGuard,
                new StudentBatchCourses(courseMapRepository));
    }

    @Test
    void addingToASecondRegularBatchForTheSameCourseIsRejected() {
        Batch existingRegularBatch = Batch.builder().id(UUID.randomUUID()).courseId(courseId).batchType(BatchType.REGULAR).build();
        Batch targetBatch = Batch.builder().id(UUID.randomUUID()).courseId(courseId).batchType(BatchType.REGULAR).build();

        when(batchRepository.findById(targetBatch.getId())).thenReturn(java.util.Optional.of(targetBatch));
        when(batchMemberRepository.findByMembershipId(membershipId))
                .thenReturn(List.of(BatchMember.builder().batchId(existingRegularBatch.getId()).membershipId(membershipId).build()));
        when(batchRepository.findAllById(Set.of(existingRegularBatch.getId()))).thenReturn(List.of(existingRegularBatch));

        assertThatThrownBy(() -> batchService.addMember(targetBatch.getId(), membershipId))
                .isInstanceOf(ConflictException.class);

        verify(batchMemberRepository, never()).save(any());
    }

    @Test
    void studentCanJoinMultipleTemporaryBatchesFreely() {
        Batch existingRegularBatch = Batch.builder().id(UUID.randomUUID()).courseId(courseId).batchType(BatchType.REGULAR).build();
        Batch temporaryBatch = Batch.builder().id(UUID.randomUUID()).courseId(courseId).batchType(BatchType.TEMPORARY).build();

        when(batchRepository.findById(temporaryBatch.getId())).thenReturn(java.util.Optional.of(temporaryBatch));
        when(batchMemberRepository.existsByBatchIdAndMembershipId(temporaryBatch.getId(), membershipId)).thenReturn(false);

        assertThatCode(() -> batchService.addMember(temporaryBatch.getId(), membershipId)).doesNotThrowAnyException();

        verify(batchMemberRepository).save(any(BatchMember.class));
        // Temporary batches skip the cross-batch regular-membership lookup entirely.
        verify(batchMemberRepository, never()).findByMembershipId(any());
    }

    @Test
    void joiningARegularBatchForADifferentCourseIsAllowed() {
        UUID otherCourseId = UUID.randomUUID();
        Batch otherCourseRegularBatch = Batch.builder().id(UUID.randomUUID()).courseId(otherCourseId).batchType(BatchType.REGULAR).build();
        Batch targetBatch = Batch.builder().id(UUID.randomUUID()).courseId(courseId).batchType(BatchType.REGULAR).build();

        when(batchRepository.findById(targetBatch.getId())).thenReturn(java.util.Optional.of(targetBatch));
        when(batchMemberRepository.findByMembershipId(membershipId))
                .thenReturn(List.of(BatchMember.builder().batchId(otherCourseRegularBatch.getId()).membershipId(membershipId).build()));
        when(batchRepository.findAllById(Set.of(otherCourseRegularBatch.getId()))).thenReturn(List.of(otherCourseRegularBatch));
        when(batchMemberRepository.existsByBatchIdAndMembershipId(targetBatch.getId(), membershipId)).thenReturn(false);

        assertThatCode(() -> batchService.addMember(targetBatch.getId(), membershipId)).doesNotThrowAnyException();

        verify(batchMemberRepository).save(any(BatchMember.class));
    }

    @Test
    void deletingABatchWithMembersRemovesTheRosterWithoutDelinkingFirst() {
        Batch batch = Batch.builder().id(UUID.randomUUID()).courseId(courseId).batchType(BatchType.REGULAR).build();

        when(batchRepository.findById(batch.getId())).thenReturn(java.util.Optional.of(batch));
        when(classInstanceRepository.findByBatchId(batch.getId())).thenReturn(List.of());

        assertThatCode(() -> batchService.delete(batch.getId())).doesNotThrowAnyException();

        verify(batchMemberRepository).deleteByBatchId(batch.getId());
        verify(batchRepository).delete(batch);
    }

    @Test
    void deletingABatchWithAttendanceHistoryIsRejected() {
        Batch batch = Batch.builder().id(UUID.randomUUID()).courseId(courseId).batchType(BatchType.REGULAR).build();
        ClassInstance heldInstance = ClassInstance.builder().id(UUID.randomUUID()).batchId(batch.getId()).status(ClassInstanceStatus.HELD).build();

        when(batchRepository.findById(batch.getId())).thenReturn(java.util.Optional.of(batch));
        when(classInstanceRepository.findByBatchId(batch.getId())).thenReturn(List.of(heldInstance));

        assertThatThrownBy(() -> batchService.delete(batch.getId()))
                .isInstanceOf(ConflictException.class)
                .hasMessageContaining("attendance history");

        verify(batchRepository, never()).delete(any());
    }

    @Test
    void deletingAnEmptyBatchWithNoHistorySucceeds() {
        Batch batch = Batch.builder().id(UUID.randomUUID()).courseId(courseId).batchType(BatchType.REGULAR).build();

        when(batchRepository.findById(batch.getId())).thenReturn(java.util.Optional.of(batch));
        when(classInstanceRepository.findByBatchId(batch.getId())).thenReturn(List.of());

        assertThatCode(() -> batchService.delete(batch.getId())).doesNotThrowAnyException();

        verify(scheduleRepository).deleteByBatchId(batch.getId());
        verify(classInstanceRepository).deleteByBatchId(batch.getId());
        verify(batchTrainerRepository).deleteByBatchId(batch.getId());
        verify(batchRepository).delete(batch);
    }

    // ------------------------------------------------------------------
    // Per-course scoping: a Trainer granted BATCH_CREATION on one course must not be able to
    // touch another course's batches just because the coarse @RequiresFeature union let them in.
    // ------------------------------------------------------------------

    @Test
    void addingAMemberIsRejectedWhenCallerLacksBatchCreationOnThisCourse() {
        Batch batch = Batch.builder().id(UUID.randomUUID()).courseId(courseId).batchType(BatchType.REGULAR).build();
        when(batchRepository.findById(batch.getId())).thenReturn(java.util.Optional.of(batch));
        doThrow(new ForbiddenException("nope")).when(courseFeatureGuard)
                .assertAnyOfCourses(Set.of(courseId), FeatureKey.BATCH_CREATION, FeatureKey.STUDENT_REGISTRATION);

        assertThatThrownBy(() -> batchService.addMember(batch.getId(), membershipId))
                .isInstanceOf(ForbiddenException.class);

        verify(batchMemberRepository, never()).save(any());
    }

    @Test
    void removingAMemberIsRejectedWhenCallerLacksBatchCreationOnThisCourse() {
        Batch batch = Batch.builder().id(UUID.randomUUID()).courseId(courseId).batchType(BatchType.REGULAR).build();
        when(batchRepository.findById(batch.getId())).thenReturn(java.util.Optional.of(batch));
        doThrow(new ForbiddenException("nope")).when(courseFeatureGuard)
                .assertAnyOfCourses(Set.of(courseId), FeatureKey.BATCH_CREATION);

        assertThatThrownBy(() -> batchService.removeMember(batch.getId(), membershipId))
                .isInstanceOf(ForbiddenException.class);

        verify(batchMemberRepository, never()).deleteByBatchIdAndMembershipId(any(), any());
    }

    @Test
    void deletingABatchIsRejectedWhenCallerLacksBatchCreationOnThisCourse() {
        Batch batch = Batch.builder().id(UUID.randomUUID()).courseId(courseId).batchType(BatchType.REGULAR).build();
        when(batchRepository.findById(batch.getId())).thenReturn(java.util.Optional.of(batch));
        doThrow(new ForbiddenException("nope")).when(courseFeatureGuard)
                .assertAllCourses(Set.of(courseId), FeatureKey.BATCH_CREATION);

        assertThatThrownBy(() -> batchService.delete(batch.getId()))
                .isInstanceOf(ForbiddenException.class);

        verify(batchRepository, never()).delete(any());
    }

    // ------------------------------------------------------------------
    // Dates. A temporary batch is defined by its window; a regular one has none.
    // ------------------------------------------------------------------

    private com.nest.app.enrolment.dto.CreateBatchRequest createRequest(
            BatchType type, java.time.LocalDate start, java.time.LocalDate end) {
        return new com.nest.app.enrolment.dto.CreateBatchRequest(
                courseId, null, "Batch A", null, type, null, List.of(), start, end, List.of(), null);
    }

    @Test
    void aTemporaryBatchWithoutAnEndDateIsRejected() {
        // Without an end date it would never stop generating classes, which is precisely the
        // thing that distinguishes it from a regular batch.
        assertThatThrownBy(() -> batchService.create(
                createRequest(BatchType.TEMPORARY, java.time.LocalDate.of(2026, 9, 1), null)))
                .isInstanceOf(BadRequestException.class)
                .hasMessageContaining("start and an end date");

        verify(batchRepository, never()).save(any());
    }

    @Test
    void aTemporaryBatchEndingBeforeItStartsIsRejected() {
        assertThatThrownBy(() -> batchService.create(createRequest(BatchType.TEMPORARY,
                java.time.LocalDate.of(2026, 10, 1), java.time.LocalDate.of(2026, 9, 1))))
                .isInstanceOf(BadRequestException.class)
                .hasMessageContaining("on or after");

        verify(batchRepository, never()).save(any());
    }

    @Test
    void aRegularBatchGivenAnEndDateIsRejectedRatherThanSilentlyDropped() {
        // Discarding it would leave the admin believing the batch stops on that date when it
        // never will.
        assertThatThrownBy(() -> batchService.create(createRequest(BatchType.REGULAR,
                java.time.LocalDate.of(2026, 9, 1), java.time.LocalDate.of(2026, 12, 1))))
                .isInstanceOf(BadRequestException.class)
                .hasMessageContaining("cannot have an end date");

        verify(batchRepository, never()).save(any());
    }

    @Test
    void aBatchWithNoTrainerYetCanBeCreatedAndReturned() {
        when(batchRepository.save(any(Batch.class))).thenAnswer(inv -> {
            Batch b = inv.getArgument(0);
            b.setId(UUID.randomUUID());
            return b;
        });
        when(batchTrainerRepository.findByBatchIdIn(any())).thenReturn(List.of());
        when(batchMemberRepository.findByBatchIdIn(any())).thenReturn(List.of());

        // No trainers at all: the response used to throw a NullPointerException (a null key looked up
        // in an immutable empty map), so creating or listing a trainerless batch was a 500.
        var response = batchService.create(new com.nest.app.enrolment.dto.CreateBatchRequest(
                courseId, null, "Batch A", null, BatchType.REGULAR, null, List.of(),
                java.time.LocalDate.of(2026, 9, 1), null, List.of(), null));

        assertThat(response.name()).isEqualTo("Batch A");
        assertThat(response.trainerMembershipId()).isNull();
        assertThat(response.trainerName()).isNull();
    }

    @Test
    void theFirstTrainerInTheListBecomesThePrimary() {
        UUID lead = UUID.randomUUID();
        UUID accompanist = UUID.randomUUID();
        when(batchRepository.save(any(Batch.class))).thenAnswer(inv -> {
            Batch b = inv.getArgument(0);
            b.setId(UUID.randomUUID());
            return b;
        });
        when(batchTrainerRepository.findByBatchIdIn(any())).thenReturn(List.of());
        when(batchMemberRepository.findByBatchIdIn(any())).thenReturn(List.of());

        batchService.create(new com.nest.app.enrolment.dto.CreateBatchRequest(
                courseId, null, "Batch A", null, BatchType.REGULAR, null,
                // Duplicated deliberately: de-duplication must not let the repeat displace the
                // lead as primary.
                List.of(lead, accompanist, lead), java.time.LocalDate.of(2026, 9, 1), null, List.of(), null));

        org.mockito.ArgumentCaptor<Batch> saved = org.mockito.ArgumentCaptor.forClass(Batch.class);
        verify(batchRepository).save(saved.capture());
        assertThat(saved.getValue().getTrainerMembershipId()).isEqualTo(lead);

        // Both trainers linked, the duplicate collapsed.
        org.mockito.ArgumentCaptor<com.nest.app.enrolment.entity.BatchTrainer> links =
                org.mockito.ArgumentCaptor.forClass(com.nest.app.enrolment.entity.BatchTrainer.class);
        verify(batchTrainerRepository, org.mockito.Mockito.times(2)).save(links.capture());
        assertThat(links.getAllValues())
                .extracting(com.nest.app.enrolment.entity.BatchTrainer::getTrainerMembershipId)
                .containsExactly(lead, accompanist);
    }

    @Test
    void aPastedMeetingLinkIsTrimmedAndABlankOneMeansNone() {
        when(batchRepository.save(any(Batch.class))).thenAnswer(inv -> {
            Batch b = inv.getArgument(0);
            b.setId(UUID.randomUUID());
            return b;
        });
        when(batchTrainerRepository.findByBatchIdIn(any())).thenReturn(List.of());
        when(batchMemberRepository.findByBatchIdIn(any())).thenReturn(List.of());

        var withLink = batchService.create(new com.nest.app.enrolment.dto.CreateBatchRequest(
                courseId, null, "Online A", null, BatchType.REGULAR, null, List.of(),
                java.time.LocalDate.of(2026, 9, 1), null, List.of(), "  https://meet.google.com/abc-defg-hij  "));
        var blank = batchService.create(new com.nest.app.enrolment.dto.CreateBatchRequest(
                courseId, null, "In person", null, BatchType.REGULAR, null, List.of(),
                java.time.LocalDate.of(2026, 9, 1), null, List.of(), "   "));

        assertThat(withLink.meetingLink()).isEqualTo("https://meet.google.com/abc-defg-hij");
        assertThat(blank.meetingLink()).isNull();
    }

    // ------------------------------------------------------------------
    // Batches that span several courses (Basic + Intermediate + Advanced).
    // ------------------------------------------------------------------

    private final UUID basic = UUID.randomUUID();
    private final UUID intermediate = UUID.randomUUID();
    private final UUID advanced = UUID.randomUUID();

    private Batch multiBatch(BatchType type, UUID... courses) {
        Batch b = Batch.builder().id(UUID.randomUUID()).batchType(type).name("Saturday").build();
        b.setCourses(List.of(courses));
        return b;
    }

    private void enrolledIn(UUID membership, UUID... courses) {
        List<com.nest.app.identity.entity.CourseMap> rows = new java.util.ArrayList<>();
        for (UUID c : courses) {
            rows.add(com.nest.app.identity.entity.CourseMap.builder().membershipId(membership).courseId(c).build());
        }
        lenient().when(courseMapRepository.findByMembershipIdIn(any())).thenReturn(rows);
    }

    private void saveAssignsAnId() {
        when(batchRepository.save(any(Batch.class))).thenAnswer(inv -> {
            Batch b = inv.getArgument(0);
            b.setId(UUID.randomUUID());
            return b;
        });
        when(batchTrainerRepository.findByBatchIdIn(any())).thenReturn(List.of());
        when(batchMemberRepository.findByBatchIdIn(any())).thenReturn(List.of());
    }

    @Test
    void aBatchCanBeCreatedAcrossSeveralCoursesWithTheFirstAsPrimary() {
        saveAssignsAnId();

        var response = batchService.create(new com.nest.app.enrolment.dto.CreateBatchRequest(
                null, List.of(basic, intermediate, advanced, basic), "Saturday", null, BatchType.REGULAR, null, List.of(),
                java.time.LocalDate.of(2026, 9, 1), null, List.of(), null));

        org.mockito.ArgumentCaptor<Batch> saved = org.mockito.ArgumentCaptor.forClass(Batch.class);
        verify(batchRepository).save(saved.capture());
        assertThat(saved.getValue().getCourseId()).isEqualTo(basic);
        assertThat(saved.getValue().allCourseIds()).containsExactly(basic, intermediate, advanced);
        assertThat(response.courses()).extracting(c -> c.id()).containsExactly(basic, intermediate, advanced);
        // The caller has to hold Batch creation on every one of them.
        verify(courseFeatureGuard).assertAllCourses(List.of(basic, intermediate, advanced), FeatureKey.BATCH_CREATION);
    }

    @Test
    void aTemporaryBatchCanSpanCoursesToo() {
        saveAssignsAnId();

        var response = batchService.create(new com.nest.app.enrolment.dto.CreateBatchRequest(
                null, List.of(basic, advanced), "Annual day", null, BatchType.TEMPORARY, null, List.of(),
                java.time.LocalDate.of(2026, 9, 1), java.time.LocalDate.of(2026, 9, 30), List.of(), null));

        assertThat(response.courses()).hasSize(2);
        assertThat(response.batchType()).isEqualTo(BatchType.TEMPORARY);
    }

    @Test
    void aBatchWithNoCourseAtAllIsRejected() {
        assertThatThrownBy(() -> batchService.create(new com.nest.app.enrolment.dto.CreateBatchRequest(
                null, List.of(), "Saturday", null, BatchType.REGULAR, null, List.of(),
                java.time.LocalDate.of(2026, 9, 1), null, List.of(), null)))
                .isInstanceOf(BadRequestException.class).hasMessageContaining("at least one course");
        verify(batchRepository, never()).save(any());
    }

    @Test
    void aCourseFromAnotherAcademyIsNotFound() {
        UUID foreign = UUID.randomUUID();
        lenient().doReturn(List.of(
                com.nest.app.curriculum.entity.Course.builder().id(foreign).academyId(UUID.randomUUID()).name("X").build()))
                .when(courseRepository).findAllById(any());

        assertThatThrownBy(() -> batchService.create(new com.nest.app.enrolment.dto.CreateBatchRequest(
                null, List.of(foreign), "Saturday", null, BatchType.REGULAR, null, List.of(),
                java.time.LocalDate.of(2026, 9, 1), null, List.of(), null)))
                .isInstanceOf(com.nest.common.exception.ResourceNotFoundException.class);
        verify(batchRepository, never()).save(any());
    }

    @Test
    void aBasicStudentInTheCombinedBatchCannotJoinAnotherRegularBatchThatCoversBasic() {
        Batch combined = multiBatch(BatchType.REGULAR, basic, intermediate, advanced);
        Batch otherBasic = multiBatch(BatchType.REGULAR, basic);
        enrolledIn(membershipId, basic);
        when(batchRepository.findById(otherBasic.getId())).thenReturn(java.util.Optional.of(otherBasic));
        when(batchMemberRepository.findByMembershipId(membershipId)).thenReturn(List.of(
                BatchMember.builder().batchId(combined.getId()).membershipId(membershipId).build()));
        when(batchRepository.findAllById(Set.of(combined.getId()))).thenReturn(List.of(combined));

        assertThatThrownBy(() -> batchService.addMember(otherBasic.getId(), membershipId))
                .isInstanceOf(ConflictException.class);
        verify(batchMemberRepository, never()).save(any());
    }

    @Test
    void aBasicStudentMayJoinARegularBatchOfCoursesTheyAreNotEnrolledIn() {
        Batch combined = multiBatch(BatchType.REGULAR, basic, intermediate, advanced);
        Batch upperOnly = multiBatch(BatchType.REGULAR, intermediate, advanced);
        enrolledIn(membershipId, basic);
        when(batchRepository.findById(upperOnly.getId())).thenReturn(java.util.Optional.of(upperOnly));
        when(batchMemberRepository.findByMembershipId(membershipId)).thenReturn(List.of(
                BatchMember.builder().batchId(combined.getId()).membershipId(membershipId).build()));
        when(batchRepository.findAllById(Set.of(combined.getId()))).thenReturn(List.of(combined));

        // In the combined batch this student holds only Basic, which the upper-only batch does not teach.
        assertThatCode(() -> batchService.addMember(upperOnly.getId(), membershipId)).doesNotThrowAnyException();
        verify(batchMemberRepository).save(any(BatchMember.class));
    }

    @Test
    void aStudentEnrolledInTwoCombinedCoursesClashesOnEitherOfThem() {
        Batch combined = multiBatch(BatchType.REGULAR, basic, intermediate, advanced);
        Batch upperOnly = multiBatch(BatchType.REGULAR, intermediate, advanced);
        enrolledIn(membershipId, basic, intermediate);
        when(batchRepository.findById(upperOnly.getId())).thenReturn(java.util.Optional.of(upperOnly));
        when(batchMemberRepository.findByMembershipId(membershipId)).thenReturn(List.of(
                BatchMember.builder().batchId(combined.getId()).membershipId(membershipId).build()));
        when(batchRepository.findAllById(Set.of(combined.getId()))).thenReturn(List.of(combined));

        // In the combined batch they hold Basic and Intermediate; the upper-only batch teaches Intermediate.
        assertThatThrownBy(() -> batchService.addMember(upperOnly.getId(), membershipId))
                .isInstanceOf(ConflictException.class);
        verify(batchMemberRepository, never()).save(any());
    }

    @Test
    void aTrainerPlacesAStudentOnlyThroughTheStudentsOwnCourse() {
        Batch combined = multiBatch(BatchType.REGULAR, basic, intermediate, advanced);
        enrolledIn(membershipId, advanced);
        when(batchRepository.findById(combined.getId())).thenReturn(java.util.Optional.of(combined));
        when(batchMemberRepository.findByMembershipId(membershipId)).thenReturn(List.of());

        batchService.addMember(combined.getId(), membershipId);

        // The check is against the Advanced course the student is on, not the batch's primary.
        verify(courseFeatureGuard).assertAnyOfCourses(Set.of(advanced),
                FeatureKey.BATCH_CREATION, FeatureKey.STUDENT_REGISTRATION);
    }

    private void twoKidsInTheBatch(Batch combined, UUID basicKid, UUID advancedKid) {
        UUID basicUser = UUID.randomUUID();
        UUID advancedUser = UUID.randomUUID();
        when(batchRepository.findById(combined.getId())).thenReturn(java.util.Optional.of(combined));
        when(batchMemberRepository.findByBatchId(combined.getId())).thenReturn(List.of(
                BatchMember.builder().batchId(combined.getId()).membershipId(basicKid).build(),
                BatchMember.builder().batchId(combined.getId()).membershipId(advancedKid).build()));
        when(courseMapRepository.findByMembershipIdIn(any())).thenReturn(List.of(
                com.nest.app.identity.entity.CourseMap.builder().membershipId(basicKid).courseId(basic).build(),
                com.nest.app.identity.entity.CourseMap.builder().membershipId(advancedKid).courseId(advanced).build()));
        when(membershipRepository.findAllById(any())).thenReturn(List.of(
                com.nest.app.identity.entity.AcademyMembership.builder().id(basicKid).userId(basicUser).build(),
                com.nest.app.identity.entity.AcademyMembership.builder().id(advancedKid).userId(advancedUser).build()));
        when(userRepository.findAllById(any())).thenReturn(List.of(
                com.nest.app.identity.entity.User.builder().id(basicUser).username("b").fullName("Basic Kid").build(),
                com.nest.app.identity.entity.User.builder().id(advancedUser).username("a").fullName("Advanced Kid").build()));
    }

    @Test
    void aTrainerSeesOnlyTheStudentsOfTheCoursesTheyHoldAndACountOfTheRest() {
        Batch combined = multiBatch(BatchType.REGULAR, basic, intermediate, advanced);
        UUID basicKid = UUID.randomUUID();
        UUID advancedKid = UUID.randomUUID();
        UUID trainer = UUID.randomUUID();
        TenantContext.set(new NestPrincipal(UUID.randomUUID(), "trainer", Role.TRAINER,
                List.of(new MembershipClaim(trainer, academyId, "Natyalaya", Role.TRAINER, Set.of(), Set.of())), trainer));
        twoKidsInTheBatch(combined, basicKid, advancedKid);
        when(courseFeatureGuard.visibleCourseIdsAny(any(String[].class)))
                .thenReturn(java.util.Optional.of(Set.of(basic, intermediate)));

        var roster = batchService.getRoster(combined.getId());

        assertThat(roster.students()).extracting(s -> s.fullName()).containsExactly("Basic Kid");
        assertThat(roster.students().get(0).courseId()).isEqualTo(basic);
        assertThat(roster.hiddenCount()).isEqualTo(1);
    }

    @Test
    void anAdminSeesEveryStudentOfAMultiCourseBatch() {
        Batch combined = multiBatch(BatchType.REGULAR, basic, advanced);
        twoKidsInTheBatch(combined, UUID.randomUUID(), UUID.randomUUID());
        when(courseFeatureGuard.visibleCourseIdsAny(any(String[].class))).thenReturn(java.util.Optional.empty());

        var roster = batchService.getRoster(combined.getId());

        assertThat(roster.students()).hasSize(2);
        assertThat(roster.hiddenCount()).isZero();
    }

    @Test
    void droppingACourseWhoseStudentsAreStillInTheBatchIsRefused() {
        Batch combined = multiBatch(BatchType.REGULAR, basic, advanced);
        UUID advancedKid = UUID.randomUUID();
        when(batchRepository.findById(combined.getId())).thenReturn(java.util.Optional.of(combined));
        when(batchMemberRepository.findByBatchId(combined.getId())).thenReturn(List.of(
                BatchMember.builder().batchId(combined.getId()).membershipId(advancedKid).build()));
        when(courseMapRepository.findByMembershipIdIn(any())).thenReturn(List.of(
                com.nest.app.identity.entity.CourseMap.builder().membershipId(advancedKid).courseId(advanced).build()));

        assertThatThrownBy(() -> batchService.update(combined.getId(),
                new com.nest.app.enrolment.dto.UpdateBatchRequest("Saturday", List.of(basic), null, null, null, null,
                        List.of(advancedKid), null)))
                .isInstanceOf(ConflictException.class).hasMessageContaining("still in this batch");
    }

    @Test
    void addingACourseNeedsBatchCreationOnThatCourse() {
        Batch combined = multiBatch(BatchType.REGULAR, basic, intermediate);
        when(batchRepository.findById(combined.getId())).thenReturn(java.util.Optional.of(combined));
        doThrow(new ForbiddenException("nope")).when(courseFeatureGuard)
                .assertCourseFeature(advanced, FeatureKey.BATCH_CREATION);

        assertThatThrownBy(() -> batchService.update(combined.getId(),
                new com.nest.app.enrolment.dto.UpdateBatchRequest("Saturday", List.of(basic, intermediate, advanced),
                        null, null, null, null, List.of(), null)))
                .isInstanceOf(ForbiddenException.class);
        verify(batchRepository, never()).save(any());
    }

    @Test
    void anEditorWhoCannotSeeSomeStudentsDoesNotRemoveThemBySavingTheRoster() {
        Batch combined = multiBatch(BatchType.REGULAR, basic, advanced);
        UUID basicKid = UUID.randomUUID();
        UUID advancedKid = UUID.randomUUID();
        when(batchRepository.findById(combined.getId())).thenReturn(java.util.Optional.of(combined));
        when(batchMemberRepository.findByBatchId(combined.getId())).thenReturn(List.of(
                BatchMember.builder().batchId(combined.getId()).membershipId(basicKid).build(),
                BatchMember.builder().batchId(combined.getId()).membershipId(advancedKid).build()));
        when(courseMapRepository.findByMembershipIdIn(any())).thenReturn(List.of(
                com.nest.app.identity.entity.CourseMap.builder().membershipId(basicKid).courseId(basic).build(),
                com.nest.app.identity.entity.CourseMap.builder().membershipId(advancedKid).courseId(advanced).build()));
        // The caller manages Basic only.
        when(courseFeatureGuard.heldCourses(Set.of(advanced), FeatureKey.BATCH_CREATION)).thenReturn(Set.of());

        // The editor was only ever sent the Basic student, so the saved roster lacks the Advanced one.
        batchService.update(combined.getId(), new com.nest.app.enrolment.dto.UpdateBatchRequest(
                "Saturday", null, null, null, null, null, List.of(basicKid), null));

        verify(batchMemberRepository, never()).deleteByBatchIdAndMembershipId(combined.getId(), advancedKid);
    }
}
