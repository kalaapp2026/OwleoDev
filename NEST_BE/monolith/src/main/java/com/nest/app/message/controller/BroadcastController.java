package com.nest.app.message.controller;

import com.nest.app.message.dto.BroadcastResponse;
import com.nest.app.message.dto.CreateBroadcastRequest;
import com.nest.app.message.service.BroadcastService;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

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
}
