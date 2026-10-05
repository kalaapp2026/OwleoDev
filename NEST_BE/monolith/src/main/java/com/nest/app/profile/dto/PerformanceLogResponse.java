package com.nest.app.profile.dto;

import java.time.LocalDate;
import java.util.UUID;

public record PerformanceLogResponse(UUID id, String title, String category, String result, LocalDate date,
                                     UUID academyId, String notes) {
}
