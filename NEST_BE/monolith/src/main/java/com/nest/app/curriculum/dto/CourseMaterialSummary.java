package com.nest.app.curriculum.dto;

import java.time.Instant;
import java.util.UUID;

/** One course on the Study Material home screen: what has been shared with it as a whole. */
public record CourseMaterialSummary(
        UUID courseId,
        String courseName,
        String courseIconKey,
        com.nest.app.curriculum.entity.CourseCategory courseCategory,
        int fileCount,
        /** Null when nothing is shared yet. */
        Instant lastUploadedAt
) {
}
