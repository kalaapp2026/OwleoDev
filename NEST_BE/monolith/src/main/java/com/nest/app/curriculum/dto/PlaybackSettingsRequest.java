package com.nest.app.curriculum.dto;

import jakarta.validation.constraints.DecimalMax;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;

import java.math.BigDecimal;
import java.util.List;

/** How one person wants a track played. Every field is optional; absent means "use the default". */
public record PlaybackSettingsRequest(
        @DecimalMin("0.25") @DecimalMax("2.00") BigDecimal speed,
        @Min(0) @Max(100) Integer volume,
        Boolean loopEnabled,

        /**
         * The parts of the file to play back-to-back with the rest skipped. Null or empty plays
         * the whole thing.
         */
        List<Segment> segments
) {
    /** Seconds from the start of the file, plus the tempo for this stretch specifically. */
    public record Segment(
            @Min(0) int start,
            @Min(0) int end,
            @DecimalMin("0.25") @DecimalMax("2.00") BigDecimal speed
    ) {
    }
}
