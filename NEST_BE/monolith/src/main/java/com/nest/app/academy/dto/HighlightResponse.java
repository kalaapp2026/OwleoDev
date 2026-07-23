package com.nest.app.academy.dto;

import java.util.List;
import java.util.UUID;

public record HighlightResponse(
        UUID id,
        String title,
        String description,
        List<String> imageUrls,
        List<HighlightTrainerResponse> trainers
) {
}
