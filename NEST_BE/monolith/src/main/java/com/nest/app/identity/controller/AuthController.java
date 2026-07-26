package com.nest.app.identity.controller;

import com.nest.app.identity.dto.AuthResponse;
import com.nest.app.identity.dto.ChangePasswordRequest;
import com.nest.app.identity.dto.IdentifyRequest;
import com.nest.app.identity.dto.IdentifyResponse;
import com.nest.app.identity.dto.LoginRequest;
import com.nest.app.identity.dto.OtpRequestDto;
import com.nest.app.identity.dto.OtpVerifyRequest;
import com.nest.app.identity.dto.RefreshRequest;
import com.nest.app.identity.dto.SignupRequest;
import com.nest.common.security.TenantContext;
import com.nest.app.identity.entity.OtpPurpose;
import com.nest.app.identity.service.AuthService;
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

    /** Single unified login entry point: one identifier (username or phone), no manual
     * "Admin/Trainer vs Student/Guest" choice. Tells the client whether to show a password or
     * OTP field next - and for OTP accounts, has already sent the code as a side effect. */
    @PostMapping("/auth/identify")
    public IdentifyResponse identify(@Valid @RequestBody IdentifyRequest request) {
        return authService.identify(request.identifier());
    }

    /** Admin/Trainer/Super Admin login - the only roles that hold a password (PRD 3.2/3.5). */
    @PostMapping("/auth/login")
    public AuthResponse login(@Valid @RequestBody LoginRequest request) {
        return authService.loginWithPassword(request.username(), request.password());
    }

    /** Public self-signup - always creates a GUEST account and logs them straight in. Becoming an
     * Artist is a separate step afterward (POST /artist-applications). */
    @PostMapping("/auth/signup")
    public AuthResponse signup(@Valid @RequestBody SignupRequest request) {
        return authService.signup(request.username(), request.password(), request.fullName(), request.phone(), request.email());
    }

    @PostMapping("/auth/otp/request")
    public ResponseEntity<Void> requestOtp(@Valid @RequestBody OtpRequestDto request) {
        if (request.purpose() == OtpPurpose.LOGIN) {
            authService.requestLoginOtp(request.identifier());
        }
        // REGISTRATION / MEMBERSHIP_CONFIRMATION purposes are triggered from enrolment-service in later phases.
        return ResponseEntity.accepted().build();
    }

    @PostMapping("/auth/otp/verify")
    public AuthResponse verifyOtp(@Valid @RequestBody OtpVerifyRequest request) {
        return authService.loginWithOtp(request.identifier(), request.code());
    }

    @PostMapping("/auth/refresh")
    public AuthResponse refresh(@Valid @RequestBody RefreshRequest request) {
        return authService.refresh(request.refreshToken());
    }

    /** Revokes the refresh token server-side - this is what makes logout actually mean something,
     * rather than just the client deleting a token it could otherwise keep using. */
    @PostMapping("/auth/logout")
    public ResponseEntity<Void> logout(@Valid @RequestBody RefreshRequest request) {
        authService.logout(request.refreshToken());
        return ResponseEntity.noContent().build();
    }

    @PostMapping("/auth/password/change")
    public ResponseEntity<Void> changePassword(@Valid @RequestBody ChangePasswordRequest request) {
        authService.changePassword(TenantContext.currentUserId(), request);
        return ResponseEntity.noContent().build();
    }
}
