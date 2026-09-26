package com.nest.app.event.service;

import com.nest.app.enrolment.entity.BatchMember;
import com.nest.app.enrolment.repository.BatchMemberRepository;
import com.nest.app.enrolment.repository.BatchRepository;
import com.nest.app.event.dto.CreateEventRequest;
import com.nest.app.event.dto.EventInterestResponse;
import com.nest.app.event.dto.EventResponse;
import com.nest.app.event.dto.InterestedPersonResponse;
import com.nest.app.event.dto.UpdateEventRequest;
import com.nest.app.event.entity.Event;
import com.nest.app.event.entity.EventAudienceType;
import com.nest.app.event.entity.EventStatus;
import com.nest.app.event.entity.EventVisibility;
import com.nest.app.event.repository.EventRepository;
import com.nest.app.identity.entity.MembershipStatus;
import com.nest.app.identity.entity.User;
import com.nest.app.identity.repository.AcademyMembershipRepository;
import com.nest.app.identity.repository.UserRepository;
import com.nest.app.identity.service.CourseFeatureGuard;
import com.nest.app.social.entity.Interest;
import com.nest.app.social.repository.InterestRepository;
import com.nest.app.social.service.PostService;
import com.nest.common.audit.Auditable;
import com.nest.common.exception.ResourceNotFoundException;
import com.nest.common.security.FeatureKey;
import com.nest.common.security.Role;
import com.nest.common.security.TenantContext;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;

/**
 * PRD 3.12. A Public+Published event is also auto-published as a Social post from the Academy's
 * verified profile; In-house never leaves the academy's own notification list. In the monolith
 * this is one direct call to {@link PostService} - the microservice cut would instead publish an
 * {@code event.published} Kafka event for social-service to consume (PRD 4.2's async layer),
 * which is worth reinstating once this module is split back out.
 *
 * <p>Audience targeting (see {@link EventAudienceType}) is deliberately metadata only: it drives
 * a real invited count and an audience badge, but every event stays visible to the whole academy's
 * list regardless of it, exactly as before this feature existed - see the module's own plan notes
 * for why per-viewer visibility filtering was left out.
 */
@Service
public class EventService {

    private final EventRepository eventRepository;
    private final PostService postService;
    private final AcademyMembershipRepository membershipRepository;
    private final BatchRepository batchRepository;
    private final BatchMemberRepository batchMemberRepository;
    private final InterestRepository interestRepository;
    private final UserRepository userRepository;
    private final CourseFeatureGuard courseFeatureGuard;

    public EventService(EventRepository eventRepository, PostService postService,
                         AcademyMembershipRepository membershipRepository, BatchRepository batchRepository,
                         BatchMemberRepository batchMemberRepository, InterestRepository interestRepository,
                         UserRepository userRepository, CourseFeatureGuard courseFeatureGuard) {
        this.eventRepository = eventRepository;
        this.postService = postService;
        this.membershipRepository = membershipRepository;
        this.batchRepository = batchRepository;
        this.batchMemberRepository = batchMemberRepository;
        this.interestRepository = interestRepository;
        this.userRepository = userRepository;
        this.courseFeatureGuard = courseFeatureGuard;
    }

    /** A per-course delegable feature only means something when the event actually names a
     * course - BY_COURSE directly, BY_BATCH indirectly through the batch's own course. The other
     * audience types (ALL_STUDENTS/ALL_TRAINERS/INDIVIDUALS) are academy-wide by construction, so
     * there is no specific course to check beyond the controller's own coarse
     * @RequiresFeature(EVENT_MANAGEMENT) union gate. */
    private void assertCanTargetAudience(EventAudienceType audienceType, Set<UUID> courseIds, Set<UUID> batchIds) {
        Set<UUID> targetCourseIds = new HashSet<>();
        if (audienceType == EventAudienceType.BY_COURSE) {
            targetCourseIds.addAll(courseIds);
        } else if (audienceType == EventAudienceType.BY_BATCH && !batchIds.isEmpty()) {
            batchRepository.findAllById(batchIds).forEach(b -> targetCourseIds.add(b.getCourseId()));
        }
        targetCourseIds.forEach(cid -> courseFeatureGuard.assertCourseFeature(cid, FeatureKey.EVENT_MANAGEMENT));
    }

    @Transactional
    @Auditable(action = "EVENT_CREATED", entityType = "event")
    public EventResponse create(CreateEventRequest request) {
        var membership = TenantContext.currentMembership();
        EventAudienceType audienceType = request.audienceType() == null ? EventAudienceType.ALL_STUDENTS : request.audienceType();
        assertCanTargetAudience(audienceType,
                request.courseIds() == null ? Set.of() : request.courseIds(),
                request.batchIds() == null ? Set.of() : request.batchIds());

        Event event = Event.builder()
                .academyId(membership.academyId())
                .type(request.type())
                .title(request.title())
                .description(request.description())
                .eventDate(request.eventDate())
                .endDate(request.endDate())
                .location(request.location())
                .venueMapsUrl(request.venueMapsUrl())
                .visibility(request.visibility())
                .coverImageUrl(request.coverImageUrl())
                .interestDeadline(request.interestDeadline())
                .status(request.status() == null ? EventStatus.PUBLISHED : request.status())
                .audienceType(audienceType)
                .courseIds(request.courseIds() == null ? new HashSet<>() : new HashSet<>(request.courseIds()))
                .batchIds(request.batchIds() == null ? new HashSet<>() : new HashSet<>(request.batchIds()))
                .individualIds(request.individualIds() == null ? new HashSet<>() : new HashSet<>(request.individualIds()))
                .createdBy(TenantContext.currentUserId())
                .build();
        event = eventRepository.save(event);
        event = maybePublishPost(event, membership.membershipId());

        return toResponse(event);
    }

    @Transactional
    @Auditable(action = "EVENT_UPDATED", entityType = "event")
    public EventResponse update(UUID id, UpdateEventRequest request) {
        Event event = findInActiveAcademyOrThrow(id);
        // Both the event's existing audience (the caller may be about to narrow away from a
        // course they don't manage) and its new one must be checked - editing must not let a
        // Trainer either grab a new course they don't hold, or quietly keep control over one
        // they never had a grant on to begin with.
        assertCanTargetAudience(event.getAudienceType(), event.getCourseIds(), event.getBatchIds());
        EventAudienceType newAudienceType = request.audienceType() == null ? EventAudienceType.ALL_STUDENTS : request.audienceType();
        Set<UUID> newCourseIds = request.courseIds() == null ? Set.of() : request.courseIds();
        Set<UUID> newBatchIds = request.batchIds() == null ? Set.of() : request.batchIds();
        assertCanTargetAudience(newAudienceType, newCourseIds, newBatchIds);

        event.setType(request.type());
        event.setTitle(request.title());
        event.setDescription(request.description());
        event.setEventDate(request.eventDate());
        event.setEndDate(request.endDate());
        event.setLocation(request.location());
        event.setVenueMapsUrl(request.venueMapsUrl());
        event.setVisibility(request.visibility());
        event.setCoverImageUrl(request.coverImageUrl());
        event.setInterestDeadline(request.interestDeadline());
        event.setAudienceType(newAudienceType);
        event.setCourseIds(new HashSet<>(newCourseIds));
        event.setBatchIds(new HashSet<>(newBatchIds));
        event.setIndividualIds(request.individualIds() == null ? new HashSet<>() : new HashSet<>(request.individualIds()));
        event = eventRepository.save(event);
        event = maybePublishPost(event, TenantContext.currentMembership().membershipId());
        return toResponse(event);
    }

    @Transactional
    @Auditable(action = "EVENT_STATUS_UPDATED", entityType = "event")
    public EventResponse updateStatus(UUID id, EventStatus status) {
        Event event = findInActiveAcademyOrThrow(id);
        assertCanTargetAudience(event.getAudienceType(), event.getCourseIds(), event.getBatchIds());
        event.setStatus(status);
        event = eventRepository.save(event);
        event = maybePublishPost(event, TenantContext.currentMembership().membershipId());
        return toResponse(event);
    }

    @Transactional
    @Auditable(action = "EVENT_DELETED", entityType = "event")
    public void delete(UUID id) {
        Event event = findInActiveAcademyOrThrow(id);
        assertCanTargetAudience(event.getAudienceType(), event.getCourseIds(), event.getBatchIds());
        eventRepository.delete(event);
    }

    @Transactional(readOnly = true)
    public EventResponse get(UUID id) {
        return toResponse(eventRepository.findById(id).orElseThrow(() -> new ResourceNotFoundException("Event not found: " + id)));
    }

    @Transactional(readOnly = true)
    public List<EventResponse> listForAcademy(UUID academyId) {
        return eventRepository.findByAcademyId(academyId).stream().map(this::toResponse).collect(Collectors.toList());
    }

    @Transactional(readOnly = true)
    public List<EventResponse> listPublic() {
        return eventRepository.findByVisibility(EventVisibility.PUBLIC).stream().map(this::toResponse).collect(Collectors.toList());
    }

    @Transactional(readOnly = true)
    public EventInterestResponse interestsFor(UUID eventId) {
        List<Interest> interests = interestRepository.findByEventId(eventId);
        if (interests.isEmpty()) {
            return new EventInterestResponse(0, List.of());
        }
        Set<UUID> userIds = interests.stream().map(Interest::getUserId).collect(Collectors.toSet());
        var usersById = userRepository.findAllById(userIds).stream()
                .collect(Collectors.toMap(User::getId, u -> u));
        List<InterestedPersonResponse> people = interests.stream()
                .map(i -> {
                    User u = usersById.get(i.getUserId());
                    return new InterestedPersonResponse(i.getUserId(), u == null ? "Unknown" : u.getFullName(),
                            u == null ? null : u.getProfileImageUrl());
                })
                .collect(Collectors.toList());
        return new EventInterestResponse(people.size(), people);
    }

    private Event findInActiveAcademyOrThrow(UUID id) {
        Event event = eventRepository.findById(id).orElseThrow(() -> new ResourceNotFoundException("Event not found: " + id));
        if (!event.getAcademyId().equals(TenantContext.currentAcademyId())) {
            throw new ResourceNotFoundException("Event not found: " + id);
        }
        return event;
    }

    /** Publishes exactly once: only the first time an event is both PUBLIC and PUBLISHED. Without
     * the postPublished guard, toggling status PUBLISHED -> CANCELLED -> PUBLISHED would post to
     * Social twice for the same event. Un-publishing (cancelling, or editing back to in-house)
     * deliberately does not retract an already-published post - see the class doc comment. */
    private Event maybePublishPost(Event event, UUID membershipId) {
        if (!event.isPostPublished() && event.getVisibility() == EventVisibility.PUBLIC && event.getStatus() == EventStatus.PUBLISHED) {
            postService.createEventReferencePost(membershipId, event.getId(), event.getTitle(), event.getCoverImageUrl());
            event.setPostPublished(true);
            event = eventRepository.save(event);
        }
        return event;
    }

    /** Real roster-derived count for who this event targets - see the class doc comment on why
     * this stops at a count rather than also exposing the roster itself. */
    private int computeInvitedCount(Event event) {
        return switch (event.getAudienceType()) {
            case ALL_STUDENTS -> (int) membershipRepository
                    .countByAcademyIdAndRoleTypeAndStatus(event.getAcademyId(), Role.STUDENT, MembershipStatus.ACTIVE);
            case ALL_TRAINERS -> (int) membershipRepository
                    .countByAcademyIdAndRoleTypeAndStatus(event.getAcademyId(), Role.TRAINER, MembershipStatus.ACTIVE);
            case BY_COURSE -> {
                if (event.getCourseIds().isEmpty()) yield 0;
                Set<UUID> batchIds = batchRepository.findByCourseIdIn(event.getCourseIds()).stream()
                        .map(b -> b.getId()).collect(Collectors.toSet());
                yield distinctMemberCount(batchIds);
            }
            case BY_BATCH -> distinctMemberCount(event.getBatchIds());
            case INDIVIDUALS -> event.getIndividualIds().size();
        };
    }

    private int distinctMemberCount(Set<UUID> batchIds) {
        if (batchIds.isEmpty()) return 0;
        return (int) batchMemberRepository.findByBatchIdIn(batchIds).stream()
                .map(BatchMember::getMembershipId)
                .distinct()
                .count();
    }

    private EventResponse toResponse(Event e) {
        int interestedCount = (int) interestRepository.countByEventId(e.getId());
        return new EventResponse(e.getId(), e.getAcademyId(), e.getType(), e.getTitle(), e.getDescription(),
                e.getEventDate(), e.getEndDate(), e.getLocation(), e.getVenueMapsUrl(), e.getVisibility(),
                e.getCoverImageUrl(), e.getInterestDeadline(), e.getStatus(), e.getAudienceType(),
                Set.copyOf(e.getCourseIds()), Set.copyOf(e.getBatchIds()), Set.copyOf(e.getIndividualIds()),
                computeInvitedCount(e), interestedCount);
    }
}
