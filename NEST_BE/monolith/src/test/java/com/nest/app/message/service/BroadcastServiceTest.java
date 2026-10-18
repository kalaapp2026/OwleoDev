package com.nest.app.message.service;

import com.nest.app.enrolment.entity.Batch;
import com.nest.app.enrolment.entity.BatchMember;
import com.nest.app.enrolment.repository.BatchMemberRepository;
import com.nest.app.enrolment.repository.BatchRepository;
import com.nest.app.curriculum.repository.CourseRepository;
import com.nest.app.event.entity.EventAudienceType;
import com.nest.app.identity.repository.UserRepository;
import com.nest.app.identity.entity.AcademyMembership;
import com.nest.app.identity.entity.MembershipStatus;
import com.nest.app.identity.repository.AcademyMembershipRepository;
import com.nest.app.message.dto.CreateBroadcastRequest;
import com.nest.app.message.entity.AcademyBroadcast;
import com.nest.app.message.repository.AcademyBroadcastRepository;
import com.nest.app.notification.entity.NotificationModule;
import com.nest.app.notification.entity.NotificationType;
import com.nest.app.notification.service.NotificationService;
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
import java.util.Set;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/** A broadcast's audience resolution mirrors EventService's exactly, and composing is Admin-only
 * since none of the 13 feature keys maps to "send a broadcast". */
@ExtendWith(MockitoExtension.class)
class BroadcastServiceTest {

    @Mock
    private AcademyBroadcastRepository broadcastRepository;
    @Mock
    private AcademyMembershipRepository membershipRepository;
    @Mock
    private BatchRepository batchRepository;
    @Mock
    private BatchMemberRepository batchMemberRepository;
    @Mock
    private NotificationService notificationService;

    @Mock
    private CourseRepository courseRepository;
    @Mock
    private UserRepository userRepository;

    private BroadcastService broadcastService;
    private final UUID academyId = UUID.randomUUID();

    private AcademyMembership active(UUID membershipId, UUID userId) {
        return AcademyMembership.builder().id(membershipId).userId(userId).academyId(academyId)
                .status(MembershipStatus.ACTIVE).build();
    }

    @BeforeEach
    void setUp() {
        broadcastService = new BroadcastService(broadcastRepository, membershipRepository,
                batchRepository, batchMemberRepository, notificationService, courseRepository, userRepository);
        // lenient: unused by the rejection test (throws first) and by the listing test (never saves).
        org.mockito.Mockito.lenient().when(broadcastRepository.save(any(AcademyBroadcast.class))).thenAnswer(inv -> {
            AcademyBroadcast b = inv.getArgument(0);
            b.setId(UUID.randomUUID());
            return b;
        });
    }

    @AfterEach
    void tearDown() {
        TenantContext.clear();
    }

    private void actingAsAdmin() {
        UUID membershipId = UUID.randomUUID();
        MembershipClaim claim = new MembershipClaim(membershipId, academyId, "Natyalaya", Role.ACADEMY_ADMIN, Set.of(), Set.of());
        TenantContext.set(new NestPrincipal(UUID.randomUUID(), "meera", Role.ACADEMY_ADMIN, List.of(claim), membershipId));
    }

    private void actingAsTrainer() {
        UUID membershipId = UUID.randomUUID();
        MembershipClaim claim = new MembershipClaim(membershipId, academyId, "Natyalaya", Role.TRAINER, Set.of(), Set.of());
        TenantContext.set(new NestPrincipal(UUID.randomUUID(), "ravi", Role.TRAINER, List.of(claim), membershipId));
    }

    @Test
    void onlyAnAcademyAdminCanSendABroadcast() {
        actingAsTrainer();
        var request = new CreateBroadcastRequest("Holiday", "No class Friday", EventAudienceType.ALL_STUDENTS, null, null, null);

        assertThatThrownBy(() -> broadcastService.create(request)).isInstanceOf(ForbiddenException.class);

        verify(broadcastRepository, never()).save(any());
        verify(notificationService, never()).notifyBroadcast(any(), any(), any(), any(), any(), any());
    }

    @Test
    void allStudentsReachesEveryActiveStudentInTheAcademy() {
        actingAsAdmin();
        UUID student1 = UUID.randomUUID();
        UUID student2 = UUID.randomUUID();
        UUID user1 = UUID.randomUUID();
        UUID user2 = UUID.randomUUID();
        when(membershipRepository.findByAcademyIdAndRoleTypeAndStatus(academyId, Role.STUDENT, MembershipStatus.ACTIVE))
                .thenReturn(List.of(
                        active(student1, user1),
                        active(student2, user2)));
        when(membershipRepository.findAllById(Set.of(student1, student2))).thenReturn(List.of(
                active(student1, user1),
                active(student2, user2)));

        var request = new CreateBroadcastRequest("Holiday", "No class Friday", EventAudienceType.ALL_STUDENTS, null, null, null);
        var response = broadcastService.create(request);

        assertThat(response.recipientCount()).isEqualTo(2);
        verify(notificationService, times(2)).notifyBroadcast(any(), eq(NotificationModule.ERP), eq(NotificationType.ACADEMY_BROADCAST), any(), any(), any());
    }

    @Test
    void byCourseResolvesThroughTheCoursesBatchesFirst() {
        actingAsAdmin();
        UUID courseId = UUID.randomUUID();
        UUID batchId = UUID.randomUUID();
        UUID membershipIdInBatch = UUID.randomUUID();
        UUID userId = UUID.randomUUID();
        when(batchRepository.findByCourseIdIn(Set.of(courseId)))
                .thenReturn(List.of(Batch.builder().id(batchId).courseId(courseId).build()));
        when(batchMemberRepository.findByBatchIdIn(Set.of(batchId)))
                .thenReturn(List.of(BatchMember.builder().batchId(batchId).membershipId(membershipIdInBatch).build()));
        when(membershipRepository.findAllById(Set.of(membershipIdInBatch)))
                .thenReturn(List.of(active(membershipIdInBatch, userId)));

        var request = new CreateBroadcastRequest("Recital", "Practice moved to Hall B",
                EventAudienceType.BY_COURSE, Set.of(courseId), Set.of(), Set.of());
        var response = broadcastService.create(request);

        assertThat(response.recipientCount()).isEqualTo(1);
        verify(notificationService).notifyBroadcast(eq(userId), eq(NotificationModule.ERP), eq(NotificationType.ACADEMY_BROADCAST),
                eq("Recital"), eq("Practice moved to Hall B"), any());
    }

    @Test
    void individualsReachesExactlyTheNamedMemberships() {
        actingAsAdmin();
        UUID membershipId = UUID.randomUUID();
        UUID userId = UUID.randomUUID();
        when(membershipRepository.findAllById(Set.of(membershipId)))
                .thenReturn(List.of(active(membershipId, userId)));

        var request = new CreateBroadcastRequest("Reminder", "Bring your costume",
                EventAudienceType.INDIVIDUALS, Set.of(), Set.of(), Set.of(membershipId));
        var response = broadcastService.create(request);

        assertThat(response.recipientCount()).isEqualTo(1);
        verify(notificationService).notifyBroadcast(eq(userId), any(), any(), any(), any(), any());
    }

    @Test
    void individualsFromAnotherAcademyOrRevokedAreNotNotified() {
        actingAsAdmin();
        UUID mine = UUID.randomUUID();
        UUID foreign = UUID.randomUUID();
        UUID revoked = UUID.randomUUID();
        UUID myUser = UUID.randomUUID();
        when(membershipRepository.findAllById(Set.of(mine, foreign, revoked))).thenReturn(List.of(
                active(mine, myUser),
                AcademyMembership.builder().id(foreign).userId(UUID.randomUUID()).academyId(UUID.randomUUID())
                        .status(MembershipStatus.ACTIVE).build(),
                AcademyMembership.builder().id(revoked).userId(UUID.randomUUID()).academyId(academyId)
                        .status(MembershipStatus.REVOKED).build()));

        var request = new CreateBroadcastRequest("Hi", "Hello", EventAudienceType.INDIVIDUALS,
                Set.of(), Set.of(), Set.of(mine, foreign, revoked));
        var response = broadcastService.create(request);

        assertThat(response.recipientCount()).isEqualTo(1);
        verify(notificationService, times(1)).notifyBroadcast(any(), any(), any(), any(), any(), any());
        verify(notificationService).notifyBroadcast(eq(myUser), any(), any(), any(), any(), any());
    }

    @Test
    void aBlankTitleIsStoredAsAnnouncement() {
        actingAsAdmin();
        when(membershipRepository.findByAcademyIdAndRoleTypeAndStatus(academyId, Role.STUDENT, MembershipStatus.ACTIVE))
                .thenReturn(List.of());

        var response = broadcastService.create(new CreateBroadcastRequest(" ", "Hello", EventAudienceType.ALL_STUDENTS, null, null, null));

        assertThat(response.title()).isEqualTo("Announcement");
    }

    @Test
    void previewCountsPeopleWithoutSendingAnything() {
        actingAsAdmin();
        UUID membershipId = UUID.randomUUID();
        when(membershipRepository.findByAcademyIdAndRoleTypeAndStatus(academyId, Role.TRAINER, MembershipStatus.ACTIVE))
                .thenReturn(List.of(active(membershipId, UUID.randomUUID())));
        when(membershipRepository.findAllById(Set.of(membershipId))).thenReturn(List.of(active(membershipId, UUID.randomUUID())));

        int count = broadcastService.preview(new com.nest.app.message.dto.AudiencePreviewRequest(
                EventAudienceType.ALL_TRAINERS, null, null, null));

        assertThat(count).isEqualTo(1);
        verify(broadcastRepository, never()).save(any());
        verify(notificationService, never()).notifyBroadcast(any(), any(), any(), any(), any(), any());
    }

    @Test
    void detailIsAdminOnly() {
        actingAsTrainer();
        assertThatThrownBy(() -> broadcastService.detail(UUID.randomUUID())).isInstanceOf(ForbiddenException.class);
    }

    @Test
    void detailOfAnotherAcademysBroadcastIsNotFound() {
        actingAsAdmin();
        UUID id = UUID.randomUUID();
        when(broadcastRepository.findById(id)).thenReturn(java.util.Optional.of(
                AcademyBroadcast.builder().id(id).academyId(UUID.randomUUID()).title("x").body("x")
                        .audienceType(EventAudienceType.ALL_STUDENTS).createdBy(UUID.randomUUID()).build()));

        assertThatThrownBy(() -> broadcastService.detail(id))
                .isInstanceOf(com.nest.common.exception.ResourceNotFoundException.class);
    }

    @Test
    void listReturnsBroadcastsForTheActiveAcademyNewestFirst() {
        actingAsAdmin();
        when(broadcastRepository.findByAcademyIdOrderByCreatedAtDesc(academyId)).thenReturn(List.of(
                AcademyBroadcast.builder().id(UUID.randomUUID()).academyId(academyId).title("A").body("a")
                        .audienceType(EventAudienceType.ALL_STUDENTS).recipientCount(3).createdBy(UUID.randomUUID()).build()));

        var results = broadcastService.list();

        assertThat(results).hasSize(1);
        assertThat(results.get(0).title()).isEqualTo("A");
    }
}
