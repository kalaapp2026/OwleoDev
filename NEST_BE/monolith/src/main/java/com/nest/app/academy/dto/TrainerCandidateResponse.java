package com.nest.app.academy.dto;

import java.util.List;
import java.util.UUID;

/** The Admin's "pick a trainer to feature" source - every active Trainer and Admin in the academy,
 * with the courses they're mapped to so the picker can tell two people apart. */
public record TrainerCandidateResponse(UUID membershipId, String fullName, String profileImageUrl, List<String> courseNames) {
}
