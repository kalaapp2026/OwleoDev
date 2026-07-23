package com.nest.identity.controller;

import com.nest.identity.dto.AuthResponse;
import com.nest.identity.dto.ChangePasswordRequest;
import com.nest.identity.dto.LoginRequest;
import com.nest.identity.dto.OtpRequestDto;
import com.nest.identity.dto.OtpVerifyRequest;
import com.nest.identity.dto.RefreshRequest;
import com.nest.common.security.TenantContext;
import com.nest.identity.entity.OtpPurpose;
import com.nest.identity.service.AuthService;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

@RestController
@Tag(name = "Auth", description = "Password login (Admin/Trainer), OTP login (Student/Guest/Artist), refresh")
public class AuthController {

    private final AuthService authService;

    public AuthController(AuthService authService) {
        this.authService = authService;
    }

    /** Admin/Trainer/Super Admin login - the only roles that hold a password (PRD 3.2/3.5). */
    @PostMapping("/auth/login")
    public AuthResponse login(@Valid @RequestBody LoginRequest request) {
        return authService.loginWithPassword(request.username(), request.password());
    }

    @PostMapping("/auth/otp/request")
    public ResponseEntity<Void> requestOtp(@Valid @RequestBody OtpRequestDto request) {
        if (request.purpose() == OtpPurpose.LOGIN) {
            authService.requestLoginOtp(request.phone());
        }
        // REGISTRATION / MEMBERSHIP_CONFIRMATION purposes are triggered from enrolment-service in later phases.
        return ResponseEntity.accepted().build();
    }

    @PostMapping("/auth/otp/verify")
    public AuthResponse verifyOtp(@Valid @RequestBody OtpVerifyRequest request) {
        return authService.loginWithOtp(request.phone(), request.code());
    }

    @PostMapping("/auth/refresh")
    public AuthResponse refresh(@Valid @RequestBody RefreshRequest request) {
        return authService.refresh(request.refreshToken());
    }

    @PostMapping("/auth/password/change")
    public ResponseEntity<Void> changePassword(@Valid @RequestBody ChangePasswordRequest request) {
        authService.changePassword(TenantContext.currentUserId(), request);
        return ResponseEntity.noContent().build();
    }
}
