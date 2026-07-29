package com.nest.app.platform.dto;

import java.time.LocalDate;
import java.util.List;
import java.util.Map;

/**
 * Everything the Super Admin console's landing dashboard shows, in one round trip - the screen is
 * a single scroll of tiles and charts, so splitting it across endpoints would just mean several
 * spinners resolving at different times.
 */
public record PlatformOverviewResponse(
        AcademyStats academies,
        UserStats users,
        ActivityStats activity,
        SocialStats social,
        List<DailyCount> signupTrend
) {

    public record AcademyStats(long total, long active, long suspended, long newThisMonth) {}

    /** {@code byRole} is keyed by the global role name (STUDENT, TRAINER, ARTIST, GUEST, ...). */
    public record UserStats(long total, Map<String, Long> byRole, long newThisWeek, long newThisMonth) {}

    /**
     * @param installsSeen distinct devices that have ever launched the app - a PROXY for store
     *                     download counts, which the backend cannot see. Labelled as such in the UI.
     */
    public record ActivityStats(long activeLastHour, long activeToday, long activeThisWeek,
                                long activeThisMonth, long installsSeen) {}

    public record SocialStats(long totalPosts, long postsThisWeek, long totalEvents,
                              long upcomingEvents, long pendingArtistApplications) {}

    public record DailyCount(LocalDate day, long count) {}
}
