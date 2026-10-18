package com.nest.app.message.controller;

import com.nest.app.message.dto.AudiencePreviewRequest;
import com.nest.app.message.dto.BroadcastDetailResponse;
import com.nest.app.message.dto.BroadcastResponse;
import com.nest.app.message.dto.CreateBroadcastRequest;
import com.nest.app.message.service.BroadcastService;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.Map;
import java.util.UUID;

/** The Messages module: an Academy Admin composes a broadcast to a resolved audience within
 * their own academy - separate from {@code /admin/notifications/broadcast}, which is a Super
 * Admin's platform-wide announcement and is untouched by this. */
@RestController
@Tag(name = "Messages")
public class BroadcastController {

    private final BroadcastService broadcastService;

    public BroadcastController(BroadcastService broadcastService) {
        this.broadcastService = broadcastService;
    }

    @PostMapping("/academies/me/broadcasts")
    public BroadcastResponse create(@Valid @RequestBody CreateBroadcastRequest request) {
        return broadcastService.create(request);
    }

    @GetMapping("/academies/me/broadcasts")
    public List<BroadcastResponse> list() {
        return broadcastService.list();
    }

    @GetMapping("/academies/me/broadcasts/{id}")
    public BroadcastDetailResponse detail(@PathVariable UUID id) {
        return broadcastService.detail(id);
    }

    @PostMapping("/academies/me/broadcasts/preview")
    public Map<String, Integer> preview(@Valid @RequestBody AudiencePreviewRequest request) {
        return Map.of("recipientCount", broadcastService.preview(request));
    }
}
