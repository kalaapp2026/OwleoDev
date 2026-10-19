package com.nest.app.academy.controller;

import com.nest.app.academy.dto.AcademySettingsDtos.CreateRequest;
import com.nest.app.academy.dto.AcademySettingsDtos.ExportResponse;
import com.nest.app.academy.dto.AcademySettingsDtos.LanguageRequest;
import com.nest.app.academy.dto.AcademySettingsDtos.RequestResponse;
import com.nest.app.academy.dto.AcademySettingsDtos.ResolveRequest;
import com.nest.app.academy.dto.AcademySettingsDtos.SettingsResponse;
import com.nest.app.academy.dto.AcademySettingsDtos.SubscriptionResponse;
import com.nest.app.academy.entity.AcademyRequestStatus;
import com.nest.app.academy.service.AcademyExportService;
import com.nest.app.academy.service.AcademyExportService.ExportFile;
import com.nest.app.academy.service.AcademySettingsService;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import org.springframework.http.ContentDisposition;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.UUID;

/**
 * Academy Settings. The {@code /academies/me/...} endpoints are for the Academy Admin of the
 * active academy and are checked in the services; the {@code /admin/academy-requests} pair is the
 * Super Admin's side of the requests an academy raises.
 */
@RestController
@Tag(name = "Academy Settings")
public class AcademySettingsController {

    private final AcademySettingsService settingsService;
    private final AcademyExportService exportService;

    public AcademySettingsController(AcademySettingsService settingsService, AcademyExportService exportService) {
        this.settingsService = settingsService;
        this.exportService = exportService;
    }

    @GetMapping("/academies/me/settings")
    public SettingsResponse settings() {
        return settingsService.settings();
    }

    @PutMapping("/academies/me/settings/language")
    public SettingsResponse updateLanguage(@Valid @RequestBody LanguageRequest request) {
        return settingsService.updateDefaultLanguage(request.defaultLanguage());
    }

    @GetMapping("/academies/me/subscription")
    public SubscriptionResponse subscription() {
        return settingsService.subscription();
    }

    @PostMapping("/academies/me/requests")
    public RequestResponse submitRequest(@Valid @RequestBody CreateRequest request) {
        return settingsService.submit(request);
    }

    @GetMapping("/academies/me/requests")
    public List<RequestResponse> myRequests() {
        return settingsService.mine();
    }

    @GetMapping("/academies/me/exports")
    public List<ExportResponse> recentExports() {
        return exportService.recent();
    }

    @GetMapping("/academies/me/exports/{kind}")
    public ResponseEntity<byte[]> export(@PathVariable String kind) {
        ExportFile file = exportService.export(kind);
        return ResponseEntity.ok()
                .contentType(new MediaType("text", "csv", java.nio.charset.StandardCharsets.UTF_8))
                .header(HttpHeaders.CONTENT_DISPOSITION, ContentDisposition.attachment().filename(file.fileName()).build().toString())
                .body(file.bytes());
    }

    @GetMapping("/admin/academy-requests")
    @PreAuthorize("hasRole('SUPER_ADMIN')")
    public List<RequestResponse> allRequests(@RequestParam(required = false) AcademyRequestStatus status) {
        return settingsService.listAll(status);
    }

    @PatchMapping("/admin/academy-requests/{id}")
    @PreAuthorize("hasRole('SUPER_ADMIN')")
    public RequestResponse resolve(@PathVariable UUID id, @Valid @RequestBody ResolveRequest request) {
        return settingsService.resolve(id, request);
    }
}
