package com.nest.app.curriculum.dto;

import java.math.BigDecimal;
import java.util.List;

/** What was saved, echoed back so the player and the server cannot drift after a save. */
public record PlaybackSettingsResponse(
        BigDecimal speed,
        int volume,
        boolean loopEnabled,
        List<PlaybackSettingsRequest.Segment> segments
) {
}
