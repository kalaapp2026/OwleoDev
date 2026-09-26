package com.nest.app.dashboard.dto;

/**
 * The Dashboard stats row: headcounts for the caller's active academy.
 *
 * <p>Deliberately just totals, not rosters - the per-course/per-trainer scoping this app is
 * careful about elsewhere (see {@code CourseFeatureGuard}) protects lists of names, not aggregate
 * counts, so this is safe to show to any member with an active academy membership.
 */
public record DashboardStatsResponse(
        int activeCourses,
        int activeBatches,
        int totalStudents,
        int totalTrainers
) {
}
