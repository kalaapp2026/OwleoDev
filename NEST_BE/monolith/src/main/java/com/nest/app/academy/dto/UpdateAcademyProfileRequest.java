package com.nest.app.academy.dto;

/** name/city/state/logoUrl are deliberately excluded - name+city form the onboarding-time unique
 * key and stay fixed, logoUrl only ever changes via the dedicated upload endpoint. Every field
 * here is optional; a blank string is treated the same as never having been filled in. */
public record UpdateAcademyProfileRequest(
        String tagline,
        String description,
        String establishedBy,
        String ownerName,
        String additionalInfo,
        String address,
        String contactNumber,
        String email,
        String instagramUrl,
        String xUrl,
        String facebookUrl,
        String youtubeUrl
) {
}
