package com.nest.app.identity.controller;

import com.nest.app.identity.dto.ArtistApplicationResponse;
import com.nest.app.identity.service.ArtistApplicationService;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.UUID;

@RestController
@Tag(name = "Artist Applications")
public class ArtistApplicationController {

    private final ArtistApplicationService applicationService;

    public ArtistApplicationController(ArtistApplicationService applicationService) {
        this.applicationService = applicationService;
    }

    /** Any authenticated Guest applies for themselves - the service checks role/duplicate state. */
    @PostMapping("/artist-applications")
    public ArtistApplicationResponse apply() {
        return applicationService.apply();
    }

    @GetMapping("/admin/artist-applications")
    @PreAuthorize("hasRole('SUPER_ADMIN')")
    public List<ArtistApplicationResponse> listPending() {
        return applicationService.listPending();
    }

    @PostMapping("/admin/artist-applications/{id}/approve")
    @PreAuthorize("hasRole('SUPER_ADMIN')")
    public ArtistApplicationResponse approve(@PathVariable UUID id) {
        return applicationService.approve(id);
    }

    @PostMapping("/admin/artist-applications/{id}/reject")
    @PreAuthorize("hasRole('SUPER_ADMIN')")
    public ArtistApplicationResponse reject(@PathVariable UUID id) {
        return applicationService.reject(id);
    }
}
