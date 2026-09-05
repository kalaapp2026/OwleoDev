package com.nest.app.curriculum.entity;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.IdClass;
import jakarta.persistence.Table;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.EqualsAndHashCode;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.annotations.UpdateTimestamp;
import org.hibernate.type.SqlTypes;

import java.io.Serializable;
import java.math.BigDecimal;
import java.time.Instant;
import java.util.UUID;

/**
 * How one person plays one track: tempo, volume, loop, and which parts of it.
 *
 * <p>Per person per track, not per track. Two trainers practising the same piece want different
 * tempos, and one silently overwriting the other's would make the feature worse than not having
 * it at all.
 */
@Entity
@Table(name = "material_playback_settings")
@IdClass(MaterialPlaybackSettings.Key.class)
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class MaterialPlaybackSettings {

    @Id
    @Column(name = "membership_id", nullable = false)
    private UUID membershipId;

    @Id
    @Column(name = "material_id", nullable = false)
    private UUID materialId;

    /** Playback rate, 0.25x to 2x. Constrained in the schema too - an out-of-range rate is noise. */
    @Column(nullable = false)
    @Builder.Default
    private BigDecimal speed = BigDecimal.ONE;

    /** 0 to 100. */
    @Column(nullable = false)
    @Builder.Default
    private int volume = 80;

    @Column(name = "loop_enabled", nullable = false)
    @Builder.Default
    private boolean loopEnabled = false;

    /**
     * The parts of the file to play back-to-back, with the rest skipped: a JSON array of
     * {@code {start, end, speed}} in seconds. Null means play the whole thing.
     *
     * <p>Stored as JSONB and handled as an opaque string rather than modelled as its own table.
     * It is a short ordered list, always read and written whole alongside its parent, and never
     * queried across rows - a table would buy joins and nothing else.
     */
    @JdbcTypeCode(SqlTypes.JSON)
    @Column(columnDefinition = "jsonb")
    private String segments;

    @UpdateTimestamp
    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;

    @Getter
    @Setter
    @NoArgsConstructor
    @AllArgsConstructor
    @EqualsAndHashCode
    public static class Key implements Serializable {
        private UUID membershipId;
        private UUID materialId;
    }
}
