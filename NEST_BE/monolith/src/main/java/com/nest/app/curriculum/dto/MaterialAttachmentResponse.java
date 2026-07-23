package com.nest.app.curriculum.dto;

import com.nest.app.curriculum.entity.ReferenceMaterialType;

import java.util.UUID;

public record MaterialAttachmentResponse(UUID id, UUID syllabusUnitId, String url, ReferenceMaterialType materialType, String contentType) {
}
