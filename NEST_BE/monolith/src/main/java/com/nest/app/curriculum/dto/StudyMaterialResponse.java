package com.nest.app.curriculum.dto;

import com.nest.app.curriculum.entity.StudyMaterialPermission;
import com.nest.app.curriculum.entity.StudyMaterialTargetType;
import com.nest.app.curriculum.entity.StudyMaterialType;
import com.nest.app.curriculum.entity.StudyMaterialVisibility;

import java.util.List;
import java.util.Set;

import java.time.Instant;
import java.util.UUID;

public record StudyMaterialResponse(
        UUID id,
        /** The material's home batch - the first batch it was aimed at; null for a file aimed only at
         * courses. */
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
        Instant uploadedAt,
        /** Who it is for: every course and batch it was aimed at, named for display. */
        List<Target> targets,
        /** Whether THIS caller may edit or delete it - needs the study-material permission on every
         * course it reaches. A trainer holding only some of them can read and use it but not change it. */
        boolean canManage
) {
    public record Target(StudyMaterialTargetType type, UUID id, String name) {
    }
}
