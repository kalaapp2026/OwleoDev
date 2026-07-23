package com.nest.app.curriculum.dto;

import com.nest.app.curriculum.entity.SyllabusUnitStatus;

import java.util.Set;
import java.util.UUID;

/** PDF/image attachments and songs are fetched separately (GET .../materials, GET .../tracks),
 * same reasoning as Track always having been separate - avoids eager-loading two more
 * collections on every list call when most callers just need the unit's own fields. */
public record SyllabusUnitResponse(
        UUID id,
        UUID courseId,
        Set<UUID> batchIds,
        String title,
        String description,
        int orderIndex,
        SyllabusUnitStatus status
) {
}
