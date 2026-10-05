package com.nest.app.academy.dto;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import java.util.List;
import java.util.UUID;

/** The whole published profile in one write - the frontend holds every edit as a local draft and
 * sends it here on Publish. logoUrl/coverImageUrl only change through their upload endpoints, or
 * are cleared with removeLogo/removeCover.
 *
 * Fields that existed before the V38 rebuild keep their old semantics (blank clears an optional
 * field). The newer ones are nullable so an older client that never sends them leaves them alone:
 * a null name/city/state keeps the current value, and a null featuredTrainers leaves the list
 * untouched, while an empty list clears it. */
public record UpdateAcademyProfileRequest(
        @Size(max = 200) String name,
        @Size(max = 300) String tagline,
        String description,
        String establishedBy,
        String ownerName,
        String additionalInfo,
        String address,
        @Size(max = 200) String area,
        @Size(max = 100) String city,
        @Size(max = 100) String state,
        @Size(max = 10) String pinCode,
        String contactNumber,
        String email,
        String instagramUrl,
        String xUrl,
        String facebookUrl,
        String youtubeUrl,
        String whatsapp,
        String websiteUrl,
        String mapsUrl,
        @Size(max = 20) String coverStyle,
        @Size(max = 20) String logoColor,
        List<String> hiddenLinks,
        Boolean removeLogo,
        Boolean removeCover,
        @Valid List<FeaturedTrainerEntry> featuredTrainers
) {
    /** One featured trainer, in display order. */
    public record FeaturedTrainerEntry(@NotNull UUID trainerMembershipId, @Size(max = 120) String designation) {
    }
}
