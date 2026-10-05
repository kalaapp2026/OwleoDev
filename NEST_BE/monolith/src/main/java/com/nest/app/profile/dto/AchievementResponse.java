package com.nest.app.profile.dto;

import java.time.LocalDate;
import java.util.UUID;

public record AchievementResponse(UUID id, String title, String description, String type, LocalDate date,
                                  UUID academyId) {
}
