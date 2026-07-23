package com.nest.app.academy.service;

import com.nest.app.academy.dto.AcademyResponse;
import com.nest.app.academy.dto.OnboardAcademyRequest;
import com.nest.app.academy.dto.OnboardAcademyResponse;
import com.nest.app.academy.entity.Academy;
import com.nest.app.academy.entity.AcademyStatus;
import com.nest.app.academy.repository.AcademyRepository;
import com.nest.app.identity.entity.MembershipStatus;
import com.nest.app.identity.service.IdentityRegistrationService;
import com.nest.app.identity.service.UserWithTempPassword;
import com.nest.common.audit.Auditable;
import com.nest.common.exception.ConflictException;
import com.nest.common.exception.ResourceNotFoundException;
import com.nest.common.security.Role;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.util.StringUtils;

import java.util.UUID;

/**
 * PRD 3.2 onboarding. In the microservice cut this called identity-service over HTTP with a
 * shared internal API key and could partially fail (see the old services/academy-service module's
 * comment on that trade-off) - in the monolith this is one local @Transactional method calling
 * another module's Spring bean directly, so Academy + User + Membership now commit or roll back
 * together with real ACID guarantees. That correctness gain is the main argument for staying a
 * monolith until there's an actual scaling reason to split.
 */
@Service
public class AcademyService {

    private final AcademyRepository academyRepository;
    private final IdentityRegistrationService identityRegistrationService;

    public AcademyService(AcademyRepository academyRepository, IdentityRegistrationService identityRegistrationService) {
        this.academyRepository = academyRepository;
        this.identityRegistrationService = identityRegistrationService;
    }

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

        UserWithTempPassword admin = identityRegistrationService.createUserWithPassword(
                request.adminUsername(), request.adminFullName(), request.adminPhone(), request.adminEmail(), Role.ACADEMY_ADMIN);
        identityRegistrationService.createMembership(admin.user().getId(), academy.getId(), academy.getName(),
                Role.ACADEMY_ADMIN, MembershipStatus.ACTIVE, null);

        return new OnboardAcademyResponse(toResponse(academy), admin.user().getUsername(), admin.temporaryPassword());
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
