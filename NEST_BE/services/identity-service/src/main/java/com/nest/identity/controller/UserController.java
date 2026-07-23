package com.nest.identity.controller;

import com.nest.common.security.TenantContext;
import com.nest.identity.dto.ThemeUpdateRequest;
import com.nest.identity.dto.UserProfileResponse;
import com.nest.identity.service.UserService;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

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
}
