package com.nest.app.identity.controller;

import com.nest.common.security.TenantContext;
import com.nest.app.identity.dto.PasswordResetResponse;
import com.nest.app.identity.dto.ThemeUpdateRequest;
import com.nest.app.identity.dto.UserProfileResponse;
import com.nest.app.identity.service.UserService;
import com.nest.common.security.FeatureKey;
import com.nest.common.security.RequiresFeature;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
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
import org.springframework.web.multipart.MultipartFile;

import java.util.UUID;

@RestController
@Tag(name = "Users")
public class UserController {

    private final UserService userService;

    public UserController(UserService userService) {
        this.userService = userService;
    }

    @GetMapping("/users/me")
    public UserProfileResponse me() {
        return userService.getProfile(TenantContext.currentUserId());
    }

    @PatchMapping("/users/me/theme")
    public ResponseEntity<Void> updateTheme(@Valid @RequestBody ThemeUpdateRequest request) {
        userService.updateThemePreference(TenantContext.currentUserId(), request.themePreference());
        return ResponseEntity.noContent().build();
    }

    /** Set right after registering a Student/Trainer, so the Attendance module has a face to show
     * instead of a bare membership ID - gated the same as the registration itself. */
    @PostMapping("/users/{userId}/profile-image")
    @RequiresFeature({FeatureKey.STUDENT_REGISTRATION, FeatureKey.TRAINER_REGISTRATION})
    public UserProfileResponse uploadProfileImage(@PathVariable UUID userId, @RequestParam("file") MultipartFile file) {
        return userService.updateProfileImage(userId, file);
    }

    /** Escape hatch for a lost temporary password (PRD 3.2/3.5 accounts only ever see it once).
     * Super Admin only, on purpose - an Academy Admin resetting their own Trainers is a
     * reasonable future extension but isn't wired up yet. */
    @PutMapping("/users/by-username/{username}/reset-password")
    @PreAuthorize("hasRole('SUPER_ADMIN')")
    public PasswordResetResponse resetPassword(@PathVariable String username) {
        String tempPassword = userService.resetPasswordByUsername(username);
        return new PasswordResetResponse(username, tempPassword);
    }
}
