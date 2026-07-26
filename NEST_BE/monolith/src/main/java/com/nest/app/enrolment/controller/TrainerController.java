package com.nest.app.enrolment.controller;

import com.nest.app.enrolment.dto.RegisterTrainerRequest;
import com.nest.app.enrolment.dto.TrainerDetailResponse;
import com.nest.app.enrolment.dto.TrainerResponse;
import com.nest.app.enrolment.dto.TrainerSummaryResponse;
import com.nest.app.enrolment.dto.UpdateTrainerRequest;
import com.nest.app.enrolment.service.TrainerRegistrationService;
import com.nest.common.security.FeatureKey;
import com.nest.common.security.RequiresFeature;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.UUID;

@RestController
@Tag(name = "Trainers")
public class TrainerController {

    private final TrainerRegistrationService trainerRegistrationService;

    public TrainerController(TrainerRegistrationService trainerRegistrationService) {
        this.trainerRegistrationService = trainerRegistrationService;
    }

    @PostMapping("/trainers")
    @RequiresFeature(FeatureKey.TRAINER_REGISTRATION)
    public TrainerResponse register(@Valid @RequestBody RegisterTrainerRequest request) {
        return trainerRegistrationService.registerTrainer(request);
    }

    /** Pre-fills the trainer edit form (profile + per-course features). */
    @GetMapping("/trainers/{membershipId}")
    @RequiresFeature(FeatureKey.TRAINER_REGISTRATION)
    public TrainerDetailResponse detail(@PathVariable UUID membershipId) {
        return trainerRegistrationService.getTrainerDetail(membershipId);
    }

    @PutMapping("/trainers/{membershipId}")
    @RequiresFeature(FeatureKey.TRAINER_REGISTRATION)
    public TrainerResponse update(@PathVariable UUID membershipId, @Valid @RequestBody UpdateTrainerRequest request) {
        return trainerRegistrationService.updateTrainer(membershipId, request);
    }

    /** Batch default-trainer picker + Users management screen. includeInactive=false (default,
     * picker) drops course-deactivated trainers; true (management view) keeps them, flagged. */
    @GetMapping("/courses/{courseId}/trainers")
    @RequiresFeature(FeatureKey.BATCH_CREATION)
    public List<TrainerSummaryResponse> trainersForCourse(@PathVariable UUID courseId,
                                                          @RequestParam(defaultValue = "false") boolean includeInactive) {
        return trainerRegistrationService.listTrainersForCourse(courseId, includeInactive);
    }
}
