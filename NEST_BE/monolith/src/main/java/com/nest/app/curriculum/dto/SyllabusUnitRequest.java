package com.nest.app.curriculum.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;

import java.util.Set;
import java.util.UUID;

/** Empty/null batchIds means "the whole course" - anyone enrolled sees it. One or more means
 * "only these batches" (a multi-select, not a single batch). The PDF/image attachment is set
 * afterwards via the separate upload endpoint, same reasoning as batch creation's roster/schedule
 * follow-up calls - a file can't ride along with a JSON body. */
public record SyllabusUnitRequest(
        @NotNull UUID courseId,
        Set<UUID> batchIds,
        @NotBlank String title,
        String description,
        int orderIndex
) {
}
