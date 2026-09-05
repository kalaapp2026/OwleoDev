package com.nest.app.curriculum.dto;

import java.time.Instant;
import java.util.UUID;

/** One row on the Study Material home screen: a batch and what has been shared with it. */
public record BatchMaterialSummary(
        UUID batchId,
        String batchName,
        UUID courseId,
        String courseName,
        String courseIconKey,
        com.nest.app.curriculum.entity.CourseCategory courseCategory,
        com.nest.app.enrolment.entity.BatchStatus batchStatus,
        int fileCount,
        /** Null when nothing has been shared yet - distinct from an old date, and the list says
         * "No files yet" rather than showing a stale timestamp. */
        Instant lastUploadedAt
) {
}
