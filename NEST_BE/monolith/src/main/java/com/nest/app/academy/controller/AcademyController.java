package com.nest.app.academy.controller;

import com.nest.app.academy.dto.AcademyResponse;
import com.nest.app.academy.dto.OnboardAcademyRequest;
import com.nest.app.academy.dto.OnboardAcademyResponse;
import com.nest.app.academy.entity.AcademyStatus;
import com.nest.app.academy.service.AcademyService;
import com.nest.app.billing.dto.BillingDtos;
import com.nest.app.billing.service.BillingService;
import com.nest.common.exception.ForbiddenException;
import com.nest.common.security.MembershipClaim;
import com.nest.common.security.NestPrincipal;
import com.nest.common.security.Role;
import com.nest.common.security.TenantContext;
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

import java.util.List;
import java.util.UUID;

/** PRD 2.4 / 3.2: onboarding and tenant suspension are Super Admin only. */
@RestController
@Tag(name = "Academies")
public class AcademyController {

    private final AcademyService academyService;
    private final BillingService billingService;

    public AcademyController(AcademyService academyService, BillingService billingService) {
        this.academyService = academyService;
        this.billingService = billingService;
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

    /** The Academy Settings screen's read-only Billing card - an Academy Admin's own invoice
     * history. Deliberately not on {@link com.nest.app.billing.controller.BillingController},
     * which is Super-Admin-only end to end (plan changes, marking paid) - this is the one
     * self-service slice of that same data, so it lives with the other academy-scoped reads
     * instead of restructuring that controller's security boundary. */
    @GetMapping("/academies/me/invoices")
    public List<BillingDtos.InvoiceResponse> myInvoices() {
        NestPrincipal principal = TenantContext.require();
        MembershipClaim membership = principal.activeMembership()
                .orElseThrow(() -> new ForbiddenException("Request has no active academy membership"));
        if (membership.roleType() != Role.ACADEMY_ADMIN && !principal.isSuperAdmin()) {
            throw new ForbiddenException("Only the Academy Admin can view billing for this academy");
        }
        return billingService.invoicesForAcademy(TenantContext.currentAcademyId());
    }
}
