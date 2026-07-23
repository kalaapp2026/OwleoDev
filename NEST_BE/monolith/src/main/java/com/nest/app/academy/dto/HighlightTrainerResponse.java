package com.nest.app.academy.dto;

import java.util.UUID;

/** A trainer (or Academy Admin, who can also teach) shown on a highlight card and its detail
 * view - resolved from the highlight's trainerMembershipIds at read time, same reasoning as
 * FeaturedTrainerResponse but without a row id of its own (backed by a plain element collection,
 * not a separate entity). */
public record HighlightTrainerResponse(UUID membershipId, String fullName, String profileImageUrl) {
}
