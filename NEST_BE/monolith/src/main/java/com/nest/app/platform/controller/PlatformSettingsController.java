package com.nest.app.platform.controller;

import com.nest.app.platform.dto.PlatformSettingsDtos;
import com.nest.app.platform.entity.PlatformSettings;
import com.nest.app.platform.service.PlatformSettingsService;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

@RestController
@Tag(name = "Platform (Super Admin)")
public class PlatformSettingsController {

    private final PlatformSettingsService settingsService;


    public PlatformSettingsController(PlatformSettingsService settingsService) {
        this.settingsService = settingsService;
    }

    /**
     * Readable by ANY authenticated user, not just Super Admin - every client needs it on startup
     * to know which half of the app to open and whether to show the toggle. Locking it to
     * Super Admin would mean nobody else could render the shell correctly.
     */
    @GetMapping("/platform/settings")
    public PlatformSettingsDtos.Response current() {
        return toResponse(settingsService.current());
    }

    @PutMapping("/admin/platform/settings")
    @PreAuthorize("hasRole('SUPER_ADMIN')")
    public PlatformSettingsDtos.Response update(@Valid @RequestBody PlatformSettingsDtos.UpdateRequest request) {
        return toResponse(settingsService.updateAppMode(request.appMode()));
    }

    /** The booleans are derived server-side so every client agrees on what a mode means, rather
     * than each one re-implementing the rules and drifting. */
    private PlatformSettingsDtos.Response toResponse(PlatformSettings settings) {
        var mode = settings.getAppMode();
        return new PlatformSettingsDtos.Response(
                mode, mode.allowsErp(), mode.allowsSocial(), mode.allowsBoth(), mode.startsOnErp());
    }
}
