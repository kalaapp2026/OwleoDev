package com.nest.app.event.controller;

import com.nest.app.event.dto.CreateEventRequest;
import com.nest.app.event.dto.EventResponse;
import com.nest.app.event.service.EventService;
import com.nest.common.security.FeatureKey;
import com.nest.common.security.RequiresFeature;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
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

    @GetMapping("/academies/{academyId}/events")
    public List<EventResponse> listForAcademy(@PathVariable UUID academyId) {
        return eventService.listForAcademy(academyId);
    }

    @GetMapping("/events/public")
    public List<EventResponse> listPublic() {
        return eventService.listPublic();
    }
}
