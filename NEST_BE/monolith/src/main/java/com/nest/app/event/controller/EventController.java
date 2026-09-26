package com.nest.app.event.controller;

import com.nest.app.event.dto.CreateEventRequest;
import com.nest.app.event.dto.EventInterestResponse;
import com.nest.app.event.dto.EventResponse;
import com.nest.app.event.dto.EventStatusUpdateRequest;
import com.nest.app.event.dto.UpdateEventRequest;
import com.nest.app.event.service.EventService;
import com.nest.common.security.FeatureKey;
import com.nest.common.security.RequiresFeature;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.UUID;

@RestController
@Tag(name = "Events")
public class EventController {

    private final EventService eventService;

    public EventController(EventService eventService) {
        this.eventService = eventService;
    }

    @PostMapping("/events")
    @RequiresFeature(FeatureKey.EVENT_MANAGEMENT)
    public EventResponse create(@Valid @RequestBody CreateEventRequest request) {
        return eventService.create(request);
    }

    @GetMapping("/events/{id}")
    public EventResponse get(@PathVariable UUID id) {
        return eventService.get(id);
    }

    @PutMapping("/events/{id}")
    @RequiresFeature(FeatureKey.EVENT_MANAGEMENT)
    public EventResponse update(@PathVariable UUID id, @Valid @RequestBody UpdateEventRequest request) {
        return eventService.update(id, request);
    }

    @PatchMapping("/events/{id}/status")
    @RequiresFeature(FeatureKey.EVENT_MANAGEMENT)
    public EventResponse updateStatus(@PathVariable UUID id, @Valid @RequestBody EventStatusUpdateRequest request) {
        return eventService.updateStatus(id, request.status());
    }

    @DeleteMapping("/events/{id}")
    @RequiresFeature(FeatureKey.EVENT_MANAGEMENT)
    public void delete(@PathVariable UUID id) {
        eventService.delete(id);
    }

    /** Open, like the event list endpoints below - the ERP event detail screen's interested-
     * students list. */
    @GetMapping("/events/{id}/interests")
    public EventInterestResponse interests(@PathVariable UUID id) {
        return eventService.interestsFor(id);
    }

    @GetMapping("/academies/{academyId}/events")
    public List<EventResponse> listForAcademy(@PathVariable UUID academyId) {
        return eventService.listForAcademy(academyId);
    }

    @GetMapping("/events/public")
    public List<EventResponse> listPublic() {
        return eventService.listPublic();
    }
}
