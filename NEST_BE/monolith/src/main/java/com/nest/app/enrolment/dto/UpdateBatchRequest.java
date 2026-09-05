package com.nest.app.enrolment.dto;

import jakarta.validation.constraints.NotBlank;

import java.time.LocalDate;
import java.util.List;
import java.util.UUID;

/**
 * Editing a batch. Neither the course nor the batch type is changeable: both determine how the
 * batch's fees and schedule were set up, and switching either after students are enrolled would
 * silently re-scope history that has already been billed and attended against.
 */
public record UpdateBatchRequest(
        @NotBlank String name,
        String description,
        List<UUID> trainerMembershipIds,
        LocalDate startDate,
        LocalDate endDate,
        /** The complete roster. Students absent from this list are unmapped, so the form's student
         * picker round-trips as a set rather than needing separate add/remove calls. */
        List<UUID> studentMembershipIds
) {
}
