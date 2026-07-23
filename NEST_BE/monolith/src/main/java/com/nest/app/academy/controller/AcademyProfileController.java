package com.nest.app.academy.controller;

import com.nest.app.academy.dto.AcademyProfileResponse;
import com.nest.app.academy.dto.AddBranchRequest;
import com.nest.app.academy.dto.AddFeaturedTrainerRequest;
import com.nest.app.academy.dto.AddHighlightRequest;
import com.nest.app.academy.dto.BranchResponse;
import com.nest.app.academy.dto.FeaturedTrainerResponse;
import com.nest.app.academy.dto.HighlightResponse;
import com.nest.app.academy.dto.TrainerCandidateResponse;
import com.nest.app.academy.dto.UpdateAcademyProfileRequest;
import com.nest.app.academy.dto.UpdateHighlightRequest;
import com.nest.app.academy.service.AcademyProfileService;
import com.nest.common.security.FeatureKey;
import com.nest.common.security.RequiresFeature;
import com.nest.common.security.TenantContext;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
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

/** PRD 3.10 About-Us page for the caller's own active academy. Read is open to any member;
 * every mutation is @RequiresFeature(ABOUT_US_EDIT) - a non-delegable feature, so only an
 * Academy Admin (or Super Admin) ever satisfies it, never a Trainer. */
@RestController
@Tag(name = "Academy Profile")
public class AcademyProfileController {

    private final AcademyProfileService academyProfileService;

    public AcademyProfileController(AcademyProfileService academyProfileService) {
        this.academyProfileService = academyProfileService;
    }

    @GetMapping("/academies/me")
    public AcademyProfileResponse getProfile() {
        return academyProfileService.getProfile(TenantContext.currentAcademyId());
    }

    @PutMapping("/academies/me")
    @RequiresFeature(FeatureKey.ABOUT_US_EDIT)
    public AcademyProfileResponse updateProfile(@Valid @RequestBody UpdateAcademyProfileRequest request) {
        return academyProfileService.updateProfile(TenantContext.currentAcademyId(), request);
    }

    @PostMapping("/academies/me/logo")
    @RequiresFeature(FeatureKey.ABOUT_US_EDIT)
    public AcademyProfileResponse uploadLogo(@RequestParam("file") MultipartFile file) {
        return academyProfileService.uploadLogo(TenantContext.currentAcademyId(), file);
    }

    @PostMapping("/academies/me/highlights")
    @RequiresFeature(FeatureKey.ABOUT_US_EDIT)
    public HighlightResponse addHighlight(@Valid @RequestBody AddHighlightRequest request) {
        return academyProfileService.addHighlight(TenantContext.currentAcademyId(), request);
    }

    @PutMapping("/academies/me/highlights/{id}")
    @RequiresFeature(FeatureKey.ABOUT_US_EDIT)
    public HighlightResponse updateHighlight(@PathVariable UUID id, @Valid @RequestBody UpdateHighlightRequest request) {
        return academyProfileService.updateHighlight(TenantContext.currentAcademyId(), id, request);
    }

    /** A highlight can carry several photos, shown as a carousel - each call adds one more. */
    @PostMapping("/academies/me/highlights/{id}/images")
    @RequiresFeature(FeatureKey.ABOUT_US_EDIT)
    public HighlightResponse addHighlightImage(@PathVariable UUID id, @RequestParam("file") MultipartFile file) {
        return academyProfileService.addHighlightImage(TenantContext.currentAcademyId(), id, file);
    }

    @DeleteMapping("/academies/me/highlights/{id}/images/{imageId}")
    @RequiresFeature(FeatureKey.ABOUT_US_EDIT)
    public void deleteHighlightImage(@PathVariable UUID id, @PathVariable UUID imageId) {
        academyProfileService.deleteHighlightImage(TenantContext.currentAcademyId(), id, imageId);
    }

    @DeleteMapping("/academies/me/highlights/{id}")
    @RequiresFeature(FeatureKey.ABOUT_US_EDIT)
    public void deleteHighlight(@PathVariable UUID id) {
        academyProfileService.deleteHighlight(TenantContext.currentAcademyId(), id);
    }

    @GetMapping("/academies/me/trainer-candidates")
    @RequiresFeature(FeatureKey.ABOUT_US_EDIT)
    public List<TrainerCandidateResponse> listTrainerCandidates() {
        return academyProfileService.listTrainerCandidates(TenantContext.currentAcademyId());
    }

    @PostMapping("/academies/me/featured-trainers")
    @RequiresFeature(FeatureKey.ABOUT_US_EDIT)
    public FeaturedTrainerResponse addFeaturedTrainer(@Valid @RequestBody AddFeaturedTrainerRequest request) {
        return academyProfileService.addFeaturedTrainer(TenantContext.currentAcademyId(), request);
    }

    @DeleteMapping("/academies/me/featured-trainers/{id}")
    @RequiresFeature(FeatureKey.ABOUT_US_EDIT)
    public void deleteFeaturedTrainer(@PathVariable UUID id) {
        academyProfileService.deleteFeaturedTrainer(TenantContext.currentAcademyId(), id);
    }

    @PostMapping("/academies/me/branches")
    @RequiresFeature(FeatureKey.ABOUT_US_EDIT)
    public BranchResponse addBranch(@Valid @RequestBody AddBranchRequest request) {
        return academyProfileService.addBranch(TenantContext.currentAcademyId(), request);
    }

    @DeleteMapping("/academies/me/branches/{id}")
    @RequiresFeature(FeatureKey.ABOUT_US_EDIT)
    public void deleteBranch(@PathVariable UUID id) {
        academyProfileService.deleteBranch(TenantContext.currentAcademyId(), id);
    }
}
