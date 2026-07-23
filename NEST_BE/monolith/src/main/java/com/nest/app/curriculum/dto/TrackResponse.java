package com.nest.app.curriculum.dto;

import java.util.UUID;

public record TrackResponse(UUID id, UUID syllabusUnitId, String title, String url, String contentType, boolean streamOnly) {
}
