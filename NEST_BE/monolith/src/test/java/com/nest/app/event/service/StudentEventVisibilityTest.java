package com.nest.app.event.service;

import com.nest.app.enrolment.entity.Batch;
import com.nest.app.enrolment.entity.BatchMember;
import com.nest.app.enrolment.repository.BatchMemberRepository;
import com.nest.app.enrolment.repository.BatchRepository;
import com.nest.app.event.dto.EventResponse;
import com.nest.app.event.entity.Event;
import com.nest.app.event.entity.EventAudienceType;
import com.nest.app.event.entity.EventStatus;
import com.nest.app.event.entity.EventType;
import com.nest.app.event.entity.EventVisibility;
import com.nest.app.event.repository.EventRepository;
import com.nest.app.identity.repository.AcademyMembershipRepository;
import com.nest.app.identity.repository.UserRepository;
import com.nest.app.identity.service.CourseFeatureGuard;
import com.nest.app.social.repository.InterestRepository;
import com.nest.app.social.service.PostService;
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
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.when;

/** A student must only ever be shown events aimed at them. Staff keep the whole list. */
@ExtendWith(MockitoExtension.class)
class StudentEventVisibilityTest {

    @Mock EventRepository eventRepository;
    @Mock PostService postService;
    @Mock AcademyMembershipRepository membershipRepository;
    @Mock BatchRepository batchRepository;
    @Mock BatchMemberRepository batchMemberRepository;
    @Mock InterestRepository interestRepository;
    @Mock UserRepository userRepository;
    @Mock CourseFeatureGuard courseFeatureGuard;

    private EventService service;
    private final UUID academyId = UUID.randomUUID();
    private final UUID me = UUID.randomUUID();
    private final UUID myUser = UUID.randomUUID();
    private final UUID myBatch = UUID.randomUUID();
    private final UUID myCourse = UUID.randomUUID();

    @BeforeEach
    void setUp() {
        service = new EventService(eventRepository, postService, membershipRepository, batchRepository,
                batchMemberRepository, interestRepository, userRepository, courseFeatureGuard);
        lenient().when(interestRepository.countByEventId(any())).thenReturn(0L);
        lenient().when(batchMemberRepository.findByMembershipId(me))
                .thenReturn(List.of(BatchMember.builder().batchId(myBatch).membershipId(me).build()));
        lenient().when(batchRepository.findAllById(any())).thenReturn(List.of(
                Batch.builder().id(myBatch).courseId(myCourse).build()));
        asRole(Role.STUDENT);
    }

    @AfterEach
    void tearDown() {
        TenantContext.clear();
    }

    private void asRole(Role role) {
        UUID membership = role == Role.STUDENT ? me : UUID.randomUUID();
        TenantContext.set(new NestPrincipal(myUser, "u", role,
                List.of(new MembershipClaim(membership, academyId, "Owleo", role, Set.of(), Set.of())),
                membership));
    }

    private Event event(String title, EventAudienceType audience, EventStatus status,
                        Set<UUID> courses, Set<UUID> batches, Set<UUID> people) {
        return Event.builder().id(UUID.randomUUID()).academyId(academyId).type(EventType.PROGRAMME)
                .title(title).eventDate(LocalDateTime.now().plusDays(2)).visibility(EventVisibility.INHOUSE)
                .status(status).audienceType(audience)
                .courseIds(new HashSet<>(courses)).batchIds(new HashSet<>(batches))
                .individualIds(new HashSet<>(people)).build();
    }

    private List<String> titlesSeen() {
        return service.listForAcademy(academyId).stream().map(EventResponse::title).toList();
    }

    @Test
    void aStudentSeesOnlyTheEventsAimedAtThem() {
        when(eventRepository.findByAcademyId(academyId)).thenReturn(List.of(
                event("everyone", EventAudienceType.ALL_STUDENTS, EventStatus.PUBLISHED, Set.of(), Set.of(), Set.of()),
                event("trainers only", EventAudienceType.ALL_TRAINERS, EventStatus.PUBLISHED, Set.of(), Set.of(), Set.of()),
                event("my course", EventAudienceType.BY_COURSE, EventStatus.PUBLISHED, Set.of(myCourse), Set.of(), Set.of()),
                event("other course", EventAudienceType.BY_COURSE, EventStatus.PUBLISHED, Set.of(UUID.randomUUID()), Set.of(), Set.of()),
                event("my batch", EventAudienceType.BY_BATCH, EventStatus.PUBLISHED, Set.of(), Set.of(myBatch), Set.of()),
                event("other batch", EventAudienceType.BY_BATCH, EventStatus.PUBLISHED, Set.of(), Set.of(UUID.randomUUID()), Set.of()),
                event("invited", EventAudienceType.INDIVIDUALS, EventStatus.PUBLISHED, Set.of(), Set.of(), Set.of(me)),
                event("not invited", EventAudienceType.INDIVIDUALS, EventStatus.PUBLISHED, Set.of(), Set.of(), Set.of(UUID.randomUUID())),
                event("draft", EventAudienceType.ALL_STUDENTS, EventStatus.DRAFT, Set.of(), Set.of(), Set.of())));

        assertThat(titlesSeen()).containsExactlyInAnyOrder("everyone", "my course", "my batch", "invited");
    }

    @Test
    void aCancelledEventStillShowsSoTheStudentKnowsItIsOff() {
        when(eventRepository.findByAcademyId(academyId)).thenReturn(List.of(
                event("called off", EventAudienceType.ALL_STUDENTS, EventStatus.CANCELLED, Set.of(), Set.of(), Set.of())));

        assertThat(titlesSeen()).containsExactly("called off");
    }

    @Test
    void staffStillSeeEveryEvent() {
        asRole(Role.ACADEMY_ADMIN);
        when(eventRepository.findByAcademyId(academyId)).thenReturn(List.of(
                event("trainers only", EventAudienceType.ALL_TRAINERS, EventStatus.PUBLISHED, Set.of(), Set.of(), Set.of()),
                event("draft", EventAudienceType.ALL_STUDENTS, EventStatus.DRAFT, Set.of(), Set.of(), Set.of())));

        assertThat(titlesSeen()).containsExactlyInAnyOrder("trainers only", "draft");
    }
}
