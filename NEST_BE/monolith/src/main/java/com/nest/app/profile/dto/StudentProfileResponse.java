package com.nest.app.profile.dto;

import java.util.List;

/** What staff see when they open a student: the profile, plus the student's self-recorded
 * achievements and performance log. */
public record StudentProfileResponse(
        SelfProfileResponse profile,
        List<AchievementResponse> achievements,
        List<PerformanceLogResponse> performanceLogs
) {
}
