package com.nest.app.event.dto;

import java.util.List;
import java.util.UUID;

/** {@code trainers} is who a staff-facing event notifies on the trainer side - filled only for a
 * caller who can manage events, and empty for everyone else. */
public record EventInterestResponse(int count, List<InterestedPersonResponse> interested, List<NotifiedTrainer> trainers) {

    public record NotifiedTrainer(UUID membershipId, String fullName) {
    }
}
