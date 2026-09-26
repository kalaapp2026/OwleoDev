package com.nest.app.message.service;

import com.nest.app.enrolment.entity.Batch;
import com.nest.app.enrolment.entity.BatchMember;
import com.nest.app.enrolment.repository.BatchMemberRepository;
import com.nest.app.enrolment.repository.BatchRepository;
import com.nest.app.event.entity.EventAudienceType;
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

    private BroadcastService broadcastService;
    private final UUID academyId = UUID.randomUUID();

    @BeforeEach
    void setUp() {
        broadcastService = new BroadcastService(broadcastRepository, membershipRepository,
                batchRepository, batchMemberRepository, notificationService);
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
        verify(notificationService, never()).notify(any(), any(), any(), any(), any(), any());
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
                        AcademyMembership.builder().id(student1).userId(user1).build(),
                        AcademyMembership.builder().id(student2).userId(user2).build()));
        when(membershipRepository.findAllById(Set.of(student1, student2))).thenReturn(List.of(
                AcademyMembership.builder().id(student1).userId(user1).build(),
                AcademyMembership.builder().id(student2).userId(user2).build()));

        var request = new CreateBroadcastRequest("Holiday", "No class Friday", EventAudienceType.ALL_STUDENTS, null, null, null);
        var response = broadcastService.create(request);

        assertThat(response.recipientCount()).isEqualTo(2);
        verify(notificationService, times(2)).notify(any(), eq(NotificationModule.ERP), eq(NotificationType.ACADEMY_BROADCAST), any(), any(), any());
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
                .thenReturn(List.of(AcademyMembership.builder().id(membershipIdInBatch).userId(userId).build()));

        var request = new CreateBroadcastRequest("Recital", "Practice moved to Hall B",
                EventAudienceType.BY_COURSE, Set.of(courseId), Set.of(), Set.of());
        var response = broadcastService.create(request);

        assertThat(response.recipientCount()).isEqualTo(1);
        verify(notificationService).notify(eq(userId), eq(NotificationModule.ERP), eq(NotificationType.ACADEMY_BROADCAST),
                eq("Recital"), eq("Practice moved to Hall B"), any());
    }

    @Test
    void individualsReachesExactlyTheNamedMemberships() {
        actingAsAdmin();
        UUID membershipId = UUID.randomUUID();
        UUID userId = UUID.randomUUID();
        when(membershipRepository.findAllById(Set.of(membershipId)))
                .thenReturn(List.of(AcademyMembership.builder().id(membershipId).userId(userId).build()));

        var request = new CreateBroadcastRequest("Reminder", "Bring your costume",
                EventAudienceType.INDIVIDUALS, Set.of(), Set.of(), Set.of(membershipId));
        var response = broadcastService.create(request);

        assertThat(response.recipientCount()).isEqualTo(1);
        verify(notificationService).notify(eq(userId), any(), any(), any(), any(), any());
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
