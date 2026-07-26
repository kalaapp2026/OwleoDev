package com.nest.app.academy.controller;

import com.nest.app.academy.dto.AcademyResponse;
import com.nest.app.academy.dto.OnboardAcademyRequest;
import com.nest.app.academy.dto.OnboardAcademyResponse;
import com.nest.app.academy.entity.AcademyStatus;
import com.nest.app.academy.service.AcademyService;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.UUID;

/** PRD 2.4 / 3.2: onboarding and tenant suspension are Super Admin only. */
@RestController
@Tag(name = "Academies")
public class AcademyController {

    private final AcademyService academyService;

    public AcademyController(AcademyService academyService) {
        this.academyService = academyService;
    }

    @PostMapping("/academies")
    @PreAuthorize("hasRole('SUPER_ADMIN')")
    public OnboardAcademyResponse onboard(@Valid @RequestBody OnboardAcademyRequest request) {
        return academyService.onboardAcademy(request);
    }

    /** Super Admin tenant list - broadcast-console academy picker + suspend/reactivate screen. */
    @GetMapping("/academies")
    @PreAuthorize("hasRole('SUPER_ADMIN')")
    public java.util.List<AcademyResponse> listAll() {
        return academyService.listAll();
    }

    @GetMapping("/academies/{id}")
    public AcademyResponse get(@PathVariable UUID id) {
        return academyService.getAcademy(id);
    }

    @PutMapping("/academies/{id}/status")
    @PreAuthorize("hasRole('SUPER_ADMIN')")
    public AcademyResponse setStatus(@PathVariable UUID id, @RequestParam AcademyStatus status) {
        return academyService.setStatus(id, status);
    }
}
