package com.nest.app.academy.dto;

import java.util.UUID;

/** The Admin's "pick a trainer to feature" source - every active Trainer in the academy. */
public record TrainerCandidateResponse(UUID membershipId, String fullName, String profileImageUrl) {
}
