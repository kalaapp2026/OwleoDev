package com.nest.app.curriculum.dto;

import com.nest.app.curriculum.entity.StudyMaterialPermission;
import com.nest.app.curriculum.entity.StudyMaterialType;
import com.nest.app.curriculum.entity.StudyMaterialVisibility;

import java.util.Set;

import java.time.Instant;
import java.util.UUID;

public record StudyMaterialResponse(
        UUID id,
        UUID batchId,
        String title,
        String description,
        String url,
        String fileName,
        String contentType,
        StudyMaterialType fileType,
        long sizeBytes,
        StudyMaterialPermission permission,
        StudyMaterialVisibility visibility,
        /** Who it was shared with when visibility is SELECTED; empty otherwise. */
        Set<UUID> studentIds,
        UUID uploadedBy,
        /** Resolved for display - students see who shared it, not a UUID. */
        String uploadedByName,
        Instant uploadedAt
) {
}
