package com.nest.app.selfservice.dto;

import java.util.UUID;

/** A course the caller is not enrolled in, with whether they have already said they are interested. */
public record ExploreCourseResponse(UUID id, String name, String category, String description,
                                    String durationLevel, String iconKey, boolean interested) {
}
