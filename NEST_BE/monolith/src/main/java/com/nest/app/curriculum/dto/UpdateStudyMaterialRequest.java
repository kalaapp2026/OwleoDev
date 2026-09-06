package com.nest.app.curriculum.dto;

import com.nest.app.curriculum.entity.StudyMaterialPermission;
import com.nest.app.curriculum.entity.StudyMaterialVisibility;

import java.util.Set;
import java.util.UUID;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

/** Editing a material's details. The file itself is replaced by re-uploading, not patched here. */
public record UpdateStudyMaterialRequest(
        @NotBlank @Size(max = 200) String title,
        @Size(max = 200) String description,
        @NotNull StudyMaterialPermission permission,

        /** ALL or SELECTED. Null is read as ALL, so an older client cannot silently narrow it. */
        StudyMaterialVisibility visibility,

        /** Membership ids, honoured only when visibility is SELECTED. */
        Set<UUID> studentIds
) {
}
