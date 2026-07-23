package com.nest.app.academy.dto;

import java.util.List;
import java.util.UUID;

/** The full About-Us page in one read - a singleton per academy, so (unlike syllabus
 * units/tracks) there's no separate-listing-endpoint concern here worth splitting apart for. Any
 * field the Admin never filled in comes back null; the frontend simply doesn't render that row
 * ("if any field is empty it's not shown"). */
public record AcademyProfileResponse(
        UUID id,
        String name,
        String tagline,
        String logoUrl,
        String description,
        String establishedBy,
        String ownerName,
        String additionalInfo,
        String address,
        String city,
        String state,
        String contactNumber,
        String email,
        String instagramUrl,
        String xUrl,
        String facebookUrl,
        String youtubeUrl,
        List<HighlightResponse> highlights,
        List<FeaturedTrainerResponse> featuredTrainers,
        List<BranchResponse> branches
) {
}
