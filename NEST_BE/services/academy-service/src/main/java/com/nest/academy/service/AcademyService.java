package com.nest.academy.service;

import com.nest.academy.client.IdentityAdminProvisionRequest;
import com.nest.academy.client.IdentityAdminProvisionResponse;
import com.nest.academy.client.IdentityServiceClient;
import com.nest.academy.dto.AcademyResponse;
import com.nest.academy.dto.OnboardAcademyRequest;
import com.nest.academy.dto.OnboardAcademyResponse;
import com.nest.academy.entity.Academy;
import com.nest.academy.entity.AcademyStatus;
import com.nest.academy.repository.AcademyRepository;
import com.nest.common.audit.Auditable;
import com.nest.common.exception.ConflictException;
import com.nest.common.exception.ResourceNotFoundException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.util.StringUtils;

import java.util.UUID;

@Service
public class AcademyService {

    private final AcademyRepository academyRepository;
    private final IdentityServiceClient identityServiceClient;

    public AcademyService(AcademyRepository academyRepository, IdentityServiceClient identityServiceClient) {
        this.academyRepository = academyRepository;
        this.identityServiceClient = identityServiceClient;
    }

    /**
     * PRD 3.2: "Academy name + city combination should be unique... Creating the Academy
     * auto-creates an empty About-Us page and an empty Course list... The first Academy Admin
     * receives credentials via email/SMS and must reset password on first login."
     */
    @Transactional
    @Auditable(action = "ACADEMY_ONBOARDED", entityType = "academy")
    public OnboardAcademyResponse onboardAcademy(OnboardAcademyRequest request) {
        if (academyRepository.existsByNameIgnoreCaseAndCityIgnoreCase(request.academyName(), request.city())) {
            throw new ConflictException(
                    "An academy named '" + request.academyName() + "' already exists in " + request.city());
        }

        Academy academy = Academy.builder()
                .name(request.academyName())
                .category(request.category())
                .logoUrl(request.logoUrl())
                .address(request.address())
                .city(request.city())
                .state(request.state())
                .contactNumber(request.contactNumber())
                .email(request.email())
                .plan(StringUtils.hasText(request.plan()) ? request.plan() : "STANDARD")
                .status(AcademyStatus.ACTIVE)
                .build();
        academy = academyRepository.save(academy);

        // KNOWN LIMITATION (Phase 1): if this call fails, the local @Transactional rolls back the
        // Academy insert on our side - but if it fails AFTER identity-service has already
        // committed the user/membership on its side, that admin login is orphaned with no
        // matching Academy row. Two separate databases can't share one ACID transaction; the
        // correct fix is a saga (compensating delete-admin call, or an outbox + async retry) once
        // Kafka is wired (Phase 4+). Acceptable for Phase 1, not for production traffic.
        IdentityAdminProvisionResponse provisioned = identityServiceClient.provisionAcademyAdmin(
                new IdentityAdminProvisionRequest(request.adminUsername(), request.adminFullName(),
                        request.adminPhone(), request.adminEmail(), academy.getId(), academy.getName()));

        return new OnboardAcademyResponse(toResponse(academy), provisioned.username(), provisioned.temporaryPassword());
    }

    @Transactional(readOnly = true)
    public AcademyResponse getAcademy(UUID id) {
        return academyRepository.findById(id).map(this::toResponse)
                .orElseThrow(() -> new ResourceNotFoundException("Academy not found: " + id));
    }

    @Transactional
    @Auditable(action = "ACADEMY_STATUS_CHANGED", entityType = "academy")
    public AcademyResponse setStatus(UUID id, AcademyStatus status) {
        Academy academy = academyRepository.findById(id)
                .orElseThrow(() -> new ResourceNotFoundException("Academy not found: " + id));
        academy.setStatus(status);
        return toResponse(academyRepository.save(academy));
    }

    private AcademyResponse toResponse(Academy academy) {
        return new AcademyResponse(academy.getId(), academy.getName(), academy.getCategory(), academy.getLogoUrl(),
                academy.getAddress(), academy.getCity(), academy.getState(), academy.getContactNumber(),
                academy.getEmail(), academy.getPlan(), academy.getStatus());
    }
}
