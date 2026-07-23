package com.nest.app.event.service;

import com.nest.app.event.dto.CreateEventRequest;
import com.nest.app.event.dto.EventResponse;
import com.nest.app.event.entity.Event;
import com.nest.app.event.entity.EventVisibility;
import com.nest.app.event.repository.EventRepository;
import com.nest.app.social.service.PostService;
import com.nest.common.audit.Auditable;
import com.nest.common.security.TenantContext;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.UUID;
import java.util.stream.Collectors;

/**
 * PRD 3.12. A Public event is also auto-published as a Social post from the Academy's verified
 * profile; In-house never leaves the academy's own notification list. In the monolith this is
 * one direct call to {@link PostService} - the microservice cut would instead publish an
 * {@code event.published} Kafka event for social-service to consume (PRD 4.2's async layer),
 * which is worth reinstating once this module is split back out.
 */
@Service
public class EventService {

    private final EventRepository eventRepository;
    private final PostService postService;

    public EventService(EventRepository eventRepository, PostService postService) {
        this.eventRepository = eventRepository;
        this.postService = postService;
    }

    @Transactional
    @Auditable(action = "EVENT_CREATED", entityType = "event")
    public EventResponse create(CreateEventRequest request) {
        var membership = TenantContext.currentMembership();

        Event event = Event.builder()
                .academyId(membership.academyId())
                .type(request.type())
                .title(request.title())
                .description(request.description())
                .eventDate(request.eventDate())
                .location(request.location())
                .visibility(request.visibility())
                .coverImageUrl(request.coverImageUrl())
                .createdBy(TenantContext.currentUserId())
                .build();
        event = eventRepository.save(event);

        if (event.getVisibility() == EventVisibility.PUBLIC) {
            postService.createEventReferencePost(membership.membershipId(), event.getId(), event.getTitle(), event.getCoverImageUrl());
        }

        return toResponse(event);
    }

    @Transactional(readOnly = true)
    public List<EventResponse> listForAcademy(UUID academyId) {
        return eventRepository.findByAcademyId(academyId).stream().map(this::toResponse).collect(Collectors.toList());
    }

    @Transactional(readOnly = true)
    public List<EventResponse> listPublic() {
        return eventRepository.findByVisibility(EventVisibility.PUBLIC).stream().map(this::toResponse).collect(Collectors.toList());
    }

    private EventResponse toResponse(Event e) {
        return new EventResponse(e.getId(), e.getAcademyId(), e.getType(), e.getTitle(), e.getDescription(),
                e.getEventDate(), e.getLocation(), e.getVisibility(), e.getCoverImageUrl());
    }
}
