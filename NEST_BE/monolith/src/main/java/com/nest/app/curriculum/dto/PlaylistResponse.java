package com.nest.app.curriculum.dto;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

/**
 * A playlist and its running order.
 *
 * <p>Entries carry the resolved material rather than just an id: the screen renders a track list,
 * and a client that had to fetch each material separately would issue one request per row.
 */
public record PlaylistResponse(
        UUID id,
        String name,
        Instant createdAt,
        List<PlaylistEntryResponse> entries
) {
    /**
     * One appearance of a material in the order.
     *
     * <p>[entryId] is what actions address, not [material.id]: the same piece can appear twice in
     * one playlist, and removing "the material" would take out both.
     */
    public record PlaylistEntryResponse(
            UUID entryId,
            int position,
            StudyMaterialResponse material
    ) {
    }
}
