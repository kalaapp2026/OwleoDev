package com.nest.app.event.service;

import com.nest.app.enrolment.entity.Batch;
import com.nest.app.enrolment.entity.BatchMember;
import com.nest.app.enrolment.repository.BatchMemberRepository;
import com.nest.app.enrolment.repository.BatchRepository;
import com.nest.app.event.dto.CreateEventRequest;
import com.nest.app.event.dto.EventResponse;
import com.nest.app.event.dto.UpdateEventRequest;
import com.nest.app.event.entity.Event;
import com.nest.app.event.entity.EventAudienceType;
import com.nest.app.event.entity.EventStatus;
import com.nest.app.event.entity.EventType;
import com.nest.app.event.entity.EventVisibility;
import com.nest.app.event.repository.EventRepository;
import com.nest.app.identity.entity.MembershipStatus;
import com.nest.app.identity.repository.AcademyMembershipRepository;
import com.nest.app.identity.repository.UserRepository;
import com.nest.app.identity.service.CourseFeatureGuard;
import com.nest.app.social.repository.InterestRepository;
import com.nest.app.social.service.PostService;
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

import java.time.LocalDateTime;
import java.util.List;
import java.util.Set;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class EventServiceTest {

    @Mock
    private EventRepository eventRepository;
    @Mock
    private PostService postService;
    @Mock
    private AcademyMembershipRepository membershipRepository;
    @Mock
    private BatchRepository batchRepository;
    @Mock
    private BatchMemberRepository batchMemberRepository;
    @Mock
    private InterestRepository interestRepository;
    @Mock
    private UserRepository userRepository;
    @Mock
    private CourseFeatureGuard courseFeatureGuard;

    private EventService eventService;

    private final UUID academyId = UUID.randomUUID();

    @BeforeEach
    void setUp() {
        eventService = new EventService(eventRepository, postService, membershipRepository, batchRepository,
                batchMemberRepository, interestRepository, userRepository, courseFeatureGuard);
        UUID adminMembershipId = UUID.randomUUID();
        MembershipClaim claim = new MembershipClaim(adminMembershipId, academyId, "Natyalaya",
                Role.ACADEMY_ADMIN, Set.of(), Set.of());
        TenantContext.set(new NestPrincipal(UUID.randomUUID(), "meera", Role.ACADEMY_ADMIN, List.of(claim), adminMembershipId));
    }

    /** eventRepository.save just returns whatever it was given, like a real save() would for an
     * already-built entity - lets the service's own mutations be observed afterward. Only stubbed
     * where a test actually reaches a save() call - the ownership-check tests throw before ever
     * getting there, and Mockito's strict stubbing flags an unused stub as a test smell. */
    private void stubSaveToEcho() {
        when(eventRepository.save(any(Event.class))).thenAnswer(inv -> inv.getArgument(0));
    }

    @AfterEach
    void tearDown() {
        TenantContext.clear();
    }

    private CreateEventRequest baseRequest(EventAudienceType audienceType, EventStatus status, EventVisibility visibility) {
        return new CreateEventRequest(EventType.PROGRAMME, "Annual Day", "desc", LocalDateTime.now().plusDays(1), null,
                "Main Hall", null, visibility, null, null, status, audienceType, Set.of(), Set.of(), Set.of());
    }

    @Test
    void invitedCountForAllStudentsReadsTheRealRoster() {
        stubSaveToEcho();
        when(membershipRepository.countByAcademyIdAndRoleTypeAndStatus(academyId, Role.STUDENT, MembershipStatus.ACTIVE)).thenReturn(42L);
        when(interestRepository.countByEventId(any())).thenReturn(0L);

        EventResponse response = eventService.create(baseRequest(EventAudienceType.ALL_STUDENTS, EventStatus.DRAFT, EventVisibility.INHOUSE));

        assertThat(response.invitedCount()).isEqualTo(42);
    }

    @Test
    void invitedCountForByBatchCountsDistinctMembersAcrossTheSelectedBatches() {
        stubSaveToEcho();
        UUID batch1 = UUID.randomUUID();
        UUID batch2 = UUID.randomUUID();
        UUID sharedMember = UUID.randomUUID();
        when(batchMemberRepository.findByBatchIdIn(Set.of(batch1, batch2))).thenReturn(List.of(
                BatchMember.builder().batchId(batch1).membershipId(sharedMember).build(),
                BatchMember.builder().batchId(batch1).membershipId(UUID.randomUUID()).build(),
                BatchMember.builder().batchId(batch2).membershipId(sharedMember).build()
        ));
        when(interestRepository.countByEventId(any())).thenReturn(0L);

        var request = new CreateEventRequest(EventType.PROGRAMME, "Workshop", null, LocalDateTime.now().plusDays(1), null,
                null, null, EventVisibility.INHOUSE, null, null, EventStatus.PUBLISHED, EventAudienceType.BY_BATCH,
                Set.of(), Set.of(batch1, batch2), Set.of());

        assertThat(eventService.create(request).invitedCount()).isEqualTo(2);
    }

    @Test
    void invitedCountForByCourseResolvesBatchesFirst() {
        stubSaveToEcho();
        UUID courseId = UUID.randomUUID();
        UUID batchId = UUID.randomUUID();
        when(batchRepository.findByCourseIdIn(Set.of(courseId))).thenReturn(List.of(
                Batch.builder().id(batchId).courseId(courseId).name("Batch A").build()
        ));
        when(batchMemberRepository.findByBatchIdIn(Set.of(batchId))).thenReturn(List.of(
                BatchMember.builder().batchId(batchId).membershipId(UUID.randomUUID()).build(),
                BatchMember.builder().batchId(batchId).membershipId(UUID.randomUUID()).build()
        ));
        when(interestRepository.countByEventId(any())).thenReturn(0L);

        var request = new CreateEventRequest(EventType.PROGRAMME, "Recital", null, LocalDateTime.now().plusDays(1), null,
                null, null, EventVisibility.INHOUSE, null, null, EventStatus.PUBLISHED, EventAudienceType.BY_COURSE,
                Set.of(courseId), Set.of(), Set.of());

        assertThat(eventService.create(request).invitedCount()).isEqualTo(2);
    }

    @Test
    void creatingAByCourseEventIsRejectedWhenCallerLacksEventManagementOnThatCourse() {
        UUID courseId = UUID.randomUUID();
        doThrow(new ForbiddenException("nope")).when(courseFeatureGuard)
                .assertCourseFeature(courseId, FeatureKey.EVENT_MANAGEMENT);

        var request = new CreateEventRequest(EventType.PROGRAMME, "Recital", null, LocalDateTime.now().plusDays(1), null,
                null, null, EventVisibility.INHOUSE, null, null, EventStatus.PUBLISHED, EventAudienceType.BY_COURSE,
                Set.of(courseId), Set.of(), Set.of());

        assertThatThrownBy(() -> eventService.create(request)).isInstanceOf(ForbiddenException.class);
        verify(eventRepository, never()).save(any());
    }

    @Test
    void creatingAByBatchEventIsRejectedWhenCallerLacksEventManagementOnThatBatchsCourse() {
        UUID courseId = UUID.randomUUID();
        UUID batchId = UUID.randomUUID();
        when(batchRepository.findAllById(Set.of(batchId)))
                .thenReturn(List.of(Batch.builder().id(batchId).courseId(courseId).build()));
        doThrow(new ForbiddenException("nope")).when(courseFeatureGuard)
                .assertCourseFeature(courseId, FeatureKey.EVENT_MANAGEMENT);

        var request = new CreateEventRequest(EventType.PROGRAMME, "Workshop", null, LocalDateTime.now().plusDays(1), null,
                null, null, EventVisibility.INHOUSE, null, null, EventStatus.PUBLISHED, EventAudienceType.BY_BATCH,
                Set.of(), Set.of(batchId), Set.of());

        assertThatThrownBy(() -> eventService.create(request)).isInstanceOf(ForbiddenException.class);
        verify(eventRepository, never()).save(any());
    }

    @Test
    void invitedCountForIndividualsIsJustHowManyWerePicked() {
        stubSaveToEcho();
        when(interestRepository.countByEventId(any())).thenReturn(0L);
        var request = new CreateEventRequest(EventType.PROGRAMME, "Private Session", null, LocalDateTime.now().plusDays(1), null,
                null, null, EventVisibility.INHOUSE, null, null, EventStatus.PUBLISHED, EventAudienceType.INDIVIDUALS,
                Set.of(), Set.of(), Set.of(UUID.randomUUID(), UUID.randomUUID(), UUID.randomUUID()));

        assertThat(eventService.create(request).invitedCount()).isEqualTo(3);
    }

    @Test
    void aDraftPublicEventDoesNotPublishToSocialUntilItsPublished() {
        stubSaveToEcho();
        when(interestRepository.countByEventId(any())).thenReturn(0L);

        eventService.create(baseRequest(EventAudienceType.ALL_STUDENTS, EventStatus.DRAFT, EventVisibility.PUBLIC));

        verify(postService, never()).createEventReferencePost(any(), any(), any(), any());
    }

    @Test
    void publishingADraftPublicEventPostsExactlyOnceEvenAcrossRepeatedStatusChanges() {
        stubSaveToEcho();
        when(interestRepository.countByEventId(any())).thenReturn(0L);
        UUID eventId = UUID.randomUUID();
        Event event = Event.builder().id(eventId).academyId(academyId).type(EventType.PROGRAMME).title("Recital")
                .eventDate(LocalDateTime.now().plusDays(1)).visibility(EventVisibility.PUBLIC).status(EventStatus.DRAFT)
                .audienceType(EventAudienceType.ALL_STUDENTS).postPublished(false).build();
        when(eventRepository.findById(eventId)).thenReturn(java.util.Optional.of(event));
        when(membershipRepository.countByAcademyIdAndRoleTypeAndStatus(any(), any(), any())).thenReturn(0L);

        eventService.updateStatus(eventId, EventStatus.PUBLISHED);
        eventService.updateStatus(eventId, EventStatus.CANCELLED);
        eventService.updateStatus(eventId, EventStatus.PUBLISHED);

        verify(postService, times(1)).createEventReferencePost(any(), any(), any(), any());
    }

    @Test
    void updatingAnEventFromAnotherAcademyIsRejected() {
        UUID eventId = UUID.randomUUID();
        Event event = Event.builder().id(eventId).academyId(UUID.randomUUID()).type(EventType.PROGRAMME).title("x")
                .eventDate(LocalDateTime.now()).visibility(EventVisibility.INHOUSE).status(EventStatus.PUBLISHED)
                .audienceType(EventAudienceType.ALL_STUDENTS).build();
        when(eventRepository.findById(eventId)).thenReturn(java.util.Optional.of(event));

        var request = new UpdateEventRequest(EventType.PROGRAMME, "y", null, LocalDateTime.now(), null, null, null,
                EventVisibility.INHOUSE, null, null, EventAudienceType.ALL_STUDENTS, Set.of(), Set.of(), Set.of());

        assertThatThrownBy(() -> eventService.update(eventId, request)).isInstanceOf(ResourceNotFoundException.class);
    }

    @Test
    void deletingAnEventFromAnotherAcademyIsRejected() {
        UUID eventId = UUID.randomUUID();
        Event event = Event.builder().id(eventId).academyId(UUID.randomUUID()).build();
        when(eventRepository.findById(eventId)).thenReturn(java.util.Optional.of(event));

        assertThatThrownBy(() -> eventService.delete(eventId)).isInstanceOf(ResourceNotFoundException.class);
    }

    private Event trainersEvent(UUID eventId, UUID eventAcademy, EventAudienceType type, Set<UUID> individuals) {
        return Event.builder().id(eventId).academyId(eventAcademy).audienceType(type)
                .individualIds(new java.util.HashSet<>(individuals)).build();
    }

    private com.nest.app.identity.entity.AcademyMembership trainer(UUID membershipId, UUID userId) {
        return com.nest.app.identity.entity.AcademyMembership.builder().id(membershipId).userId(userId)
                .academyId(academyId).roleType(Role.TRAINER).status(MembershipStatus.ACTIVE).build();
    }

    @Test
    void anAdminSeesTheTrainersAnAllTrainersEventNotifies() {
        UUID eventId = UUID.randomUUID();
        UUID trainerMembership = UUID.randomUUID();
        UUID trainerUser = UUID.randomUUID();
        when(interestRepository.findByEventId(eventId)).thenReturn(List.of());
        when(eventRepository.findById(eventId)).thenReturn(java.util.Optional.of(
                trainersEvent(eventId, academyId, EventAudienceType.ALL_TRAINERS, Set.of())));
        when(membershipRepository.findByAcademyIdAndRoleTypeAndStatus(academyId, Role.TRAINER, MembershipStatus.ACTIVE))
                .thenReturn(List.of(trainer(trainerMembership, trainerUser)));
        when(userRepository.findAllById(any())).thenReturn(List.of(
                com.nest.app.identity.entity.User.builder().id(trainerUser).fullName("Rahul Nair").build()));

        var response = eventService.interestsFor(eventId);

        assertThat(response.trainers()).extracting("fullName").containsExactly("Rahul Nair");
    }

    @Test
    void anIndividualsEventListsOnlyTheTrainersAmongTheNamedPeople() {
        UUID eventId = UUID.randomUUID();
        UUID trainerMembership = UUID.randomUUID();
        UUID studentMembership = UUID.randomUUID();
        UUID trainerUser = UUID.randomUUID();
        when(interestRepository.findByEventId(eventId)).thenReturn(List.of());
        when(eventRepository.findById(eventId)).thenReturn(java.util.Optional.of(
                trainersEvent(eventId, academyId, EventAudienceType.INDIVIDUALS, Set.of(trainerMembership, studentMembership))));
        when(membershipRepository.findAllById(Set.of(trainerMembership, studentMembership))).thenReturn(List.of(
                trainer(trainerMembership, trainerUser),
                com.nest.app.identity.entity.AcademyMembership.builder().id(studentMembership).userId(UUID.randomUUID())
                        .academyId(academyId).roleType(Role.STUDENT).status(MembershipStatus.ACTIVE).build()));
        when(userRepository.findAllById(any())).thenReturn(List.of(
                com.nest.app.identity.entity.User.builder().id(trainerUser).fullName("Divya Menon").build()));

        var response = eventService.interestsFor(eventId);

        assertThat(response.trainers()).extracting("fullName").containsExactly("Divya Menon");
    }

    @Test
    void aStudentDoesNotSeeWhichTrainersAnEventNotifies() {
        UUID studentMembershipId = UUID.randomUUID();
        MembershipClaim claim = new MembershipClaim(studentMembershipId, academyId, "Natyalaya", Role.STUDENT, Set.of(), Set.of());
        TenantContext.set(new NestPrincipal(UUID.randomUUID(), "kavya", Role.STUDENT, List.of(claim), studentMembershipId));
        UUID eventId = UUID.randomUUID();
        when(interestRepository.findByEventId(eventId)).thenReturn(List.of());
        when(eventRepository.findById(eventId)).thenReturn(java.util.Optional.of(
                trainersEvent(eventId, academyId, EventAudienceType.ALL_TRAINERS, Set.of())));

        assertThat(eventService.interestsFor(eventId).trainers()).isEmpty();
        verify(membershipRepository, never()).findByAcademyIdAndRoleTypeAndStatus(any(), any(), any());
    }

    @Test
    void anotherAcademysEventNeverListsItsTrainers() {
        UUID eventId = UUID.randomUUID();
        when(interestRepository.findByEventId(eventId)).thenReturn(List.of());
        when(eventRepository.findById(eventId)).thenReturn(java.util.Optional.of(
                trainersEvent(eventId, UUID.randomUUID(), EventAudienceType.ALL_TRAINERS, Set.of())));

        assertThat(eventService.interestsFor(eventId).trainers()).isEmpty();
        verify(membershipRepository, never()).findByAcademyIdAndRoleTypeAndStatus(any(), any(), any());
    }
}
