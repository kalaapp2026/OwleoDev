package com.nest.app.selfservice.dto;

import java.util.UUID;

/** A course the caller is not enrolled in, with whether they have already said they are interested.
 * {@code trainerName} and {@code schedule} ("Tue, Thu · 8:00 AM–8:45 AM") come from the course's first
 * active batch, and are null while no batch with a trainer / a weekly schedule exists. */
public record ExploreCourseResponse(UUID id, String name, String category, String description,
                                    String durationLevel, String iconKey, boolean interested,
                                    String trainerName, String schedule) {
}
