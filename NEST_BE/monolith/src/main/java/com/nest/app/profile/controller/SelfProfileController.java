package com.nest.app.profile.controller;

import com.nest.app.profile.dto.AchievementRequest;
import com.nest.app.profile.dto.AchievementResponse;
import com.nest.app.profile.dto.PerformanceLogRequest;
import com.nest.app.profile.dto.PerformanceLogResponse;
import com.nest.app.profile.dto.SelfProfileResponse;
import com.nest.app.profile.dto.StudentProfileResponse;
import com.nest.app.profile.dto.UpdateSelfProfileRequest;
import com.nest.app.profile.service.SelfProfileService;
import com.nest.common.security.TenantContext;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

import java.util.List;
import java.util.UUID;

/**
 * The signed-in person's own profile. No {@code @RequiresFeature}: it is about the caller and only
 * the caller - every method reads the user id from the token.
 */
@RestController
@Tag(name = "My profile")
public class SelfProfileController {

    private final SelfProfileService service;

    public SelfProfileController(SelfProfileService service) {
        this.service = service;
    }

    @GetMapping("/users/me/profile")
    public SelfProfileResponse profile() {
        return service.get(TenantContext.currentUserId());
    }

    @PutMapping("/users/me/profile")
    public SelfProfileResponse updateProfile(@Valid @RequestBody UpdateSelfProfileRequest request) {
        return service.update(TenantContext.currentUserId(), request);
    }

    /** Self-service photo change. The registration-time upload on UserController is gated to
     * staff; this one is the person changing their own picture. */
    @PostMapping("/users/me/profile-image")
    public SelfProfileResponse uploadPhoto(@RequestParam("file") MultipartFile file) {
        return service.updatePhoto(TenantContext.currentUserId(), file);
    }

    /** Staff view of a student - same access as GET /students/{membershipId}/card (no
     * @RequiresFeature; the service checks the student belongs to the active academy). */
    @GetMapping("/students/{membershipId}/profile")
    public StudentProfileResponse studentProfile(@PathVariable UUID membershipId) {
        return service.forStudent(membershipId);
    }

    @GetMapping("/users/me/achievements")
    public List<AchievementResponse> achievements() {
        return service.achievements(TenantContext.currentUserId());
    }

    @PostMapping("/users/me/achievements")
    public AchievementResponse addAchievement(@Valid @RequestBody AchievementRequest request) {
        return service.addAchievement(TenantContext.currentUserId(), request);
    }

    @PutMapping("/users/me/achievements/{id}")
    public AchievementResponse updateAchievement(@PathVariable UUID id, @Valid @RequestBody AchievementRequest request) {
        return service.updateAchievement(TenantContext.currentUserId(), id, request);
    }

    @DeleteMapping("/users/me/achievements/{id}")
    public ResponseEntity<Void> deleteAchievement(@PathVariable UUID id) {
        service.deleteAchievement(TenantContext.currentUserId(), id);
        return ResponseEntity.noContent().build();
    }

    @GetMapping("/users/me/performance-logs")
    public List<PerformanceLogResponse> performanceLogs() {
        return service.performanceLogs(TenantContext.currentUserId());
    }

    @PostMapping("/users/me/performance-logs")
    public PerformanceLogResponse addPerformanceLog(@Valid @RequestBody PerformanceLogRequest request) {
        return service.addPerformanceLog(TenantContext.currentUserId(), request);
    }

    @PutMapping("/users/me/performance-logs/{id}")
    public PerformanceLogResponse updatePerformanceLog(@PathVariable UUID id,
                                                       @Valid @RequestBody PerformanceLogRequest request) {
        return service.updatePerformanceLog(TenantContext.currentUserId(), id, request);
    }

    @DeleteMapping("/users/me/performance-logs/{id}")
    public ResponseEntity<Void> deletePerformanceLog(@PathVariable UUID id) {
        service.deletePerformanceLog(TenantContext.currentUserId(), id);
        return ResponseEntity.noContent().build();
    }
}
