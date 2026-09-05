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
import org.hibernate.annotations.CreationTimestamp;

import java.time.Instant;
import java.util.UUID;

/**
 * A running order over audio material - warm-ups, then the piece, then the cool-down - so a class
 * is not spent hunting for the next file between exercises.
 *
 * <p>Owned by a membership rather than a user, for the same reason salary and joining date are:
 * a trainer teaching at two academies keeps a separate set at each, and the material a playlist
 * points at belongs to one academy anyway.
 */
@Entity
@Table(name = "material_playlists", indexes =
        @Index(name = "idx_material_playlists_membership", columnList = "membership_id"))
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class MaterialPlaylist {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(name = "membership_id", nullable = false)
    private UUID membershipId;

    /** Denormalised so a playlist can be tenant-checked without joining through the membership. */
    @Column(name = "academy_id", nullable = false)
    private UUID academyId;

    @Column(nullable = false)
    private String name;

    @CreationTimestamp
    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt;
}
