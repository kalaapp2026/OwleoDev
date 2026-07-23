package com.nest.app.curriculum.dto;

import jakarta.validation.constraints.NotBlank;

import java.util.Set;
import java.util.UUID;

/** courseId is fixed at creation, same as a Course's own category/feeCycle - moving a material to
 * a different course isn't a supported edit, only its title/description/targeting/order are. */
public record UpdateSyllabusUnitRequest(
        @NotBlank String title,
        String description,
        Set<UUID> batchIds,
        int orderIndex
) {
}
