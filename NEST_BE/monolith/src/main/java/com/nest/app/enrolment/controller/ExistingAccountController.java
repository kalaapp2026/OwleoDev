package com.nest.app.enrolment.controller;

import com.nest.app.enrolment.dto.ExistingAccountDtos.CheckResponse;
import com.nest.app.enrolment.dto.ExistingAccountDtos.CodeRequest;
import com.nest.app.enrolment.dto.ExistingAccountDtos.VerifiedResponse;
import com.nest.app.enrolment.dto.ExistingAccountDtos.VerifyRequest;
import com.nest.app.enrolment.service.ExistingAccountService;
import com.nest.common.security.FeatureKey;
import com.nest.common.security.RequiresFeature;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

/**
 * Adding a person who already has a NEST account to this academy. The coarse gate here is the union
 * of the two registration features; the service then requires the one that matches the role being
 * added (the per-role check the controller annotation can't express).
 */
@RestController
@Tag(name = "Existing accounts")
public class ExistingAccountController {

    private final ExistingAccountService existingAccountService;

    public ExistingAccountController(ExistingAccountService existingAccountService) {
        this.existingAccountService = existingAccountService;
    }

    /** Is there an account for this email? Reveals only that, and a masked name. */
    @PostMapping("/existing-accounts/check")
    @RequiresFeature({FeatureKey.STUDENT_REGISTRATION, FeatureKey.TRAINER_REGISTRATION})
    public CheckResponse check(@Valid @RequestBody CodeRequest request) {
        return existingAccountService.check(request.email(), request.role());
    }

    /** Posts a confirmation code to the person's own notifications. */
    @PostMapping("/existing-accounts/send-code")
    @RequiresFeature({FeatureKey.STUDENT_REGISTRATION, FeatureKey.TRAINER_REGISTRATION})
    public ResponseEntity<Void> sendCode(@Valid @RequestBody CodeRequest request) {
        existingAccountService.sendCode(request.email(), request.role());
        return ResponseEntity.noContent().build();
    }

    /** Checks the code the person read out; on success returns their details and mappings. */
    @PostMapping("/existing-accounts/verify")
    @RequiresFeature({FeatureKey.STUDENT_REGISTRATION, FeatureKey.TRAINER_REGISTRATION})
    public VerifiedResponse verify(@Valid @RequestBody VerifyRequest request) {
        return existingAccountService.verify(request.email(), request.role(), request.code());
    }
}
