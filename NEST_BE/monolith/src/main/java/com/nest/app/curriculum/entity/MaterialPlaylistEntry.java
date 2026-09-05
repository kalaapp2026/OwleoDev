package com.nest.app.curriculum.entity;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.Id;
import jakarta.persistence.Index;
import jakarta.persistence.Table;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

import java.util.UUID;

/**
 * One appearance of a material in a playlist.
 *
 * <p>Has its own id rather than being keyed by (playlist, material), because the same piece
 * legitimately appears more than once in a running order - played slowly, then up to tempo - and
 * each appearance needs its own position. A composite key on the material would silently collapse
 * the two into one row.
 */
@Entity
@Table(name = "material_playlist_entries", indexes =
        @Index(name = "idx_material_playlist_entries_playlist", columnList = "playlist_id, position"))
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class MaterialPlaylistEntry {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(name = "playlist_id", nullable = false)
    private UUID playlistId;

    @Column(name = "material_id", nullable = false)
    private UUID materialId;

    /**
     * Zero-based position in the running order.
     *
     * <p>Rewritten as a dense 0..n-1 sequence on every reorder rather than being patched, so gaps
     * and ties cannot accumulate into an order that depends on row insertion.
     */
    @Column(name = "position", nullable = false)
    private int position;
}
