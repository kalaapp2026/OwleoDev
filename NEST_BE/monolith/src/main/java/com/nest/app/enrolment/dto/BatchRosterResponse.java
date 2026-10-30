package com.nest.app.enrolment.dto;

import java.util.List;

/**
 * A batch's roster as the CALLER may see it. A batch can span several courses, and a trainer sees only
 * the students of the courses they hold; {@code hiddenCount} is how many others are in the batch, so the
 * screen can say "3 students from other courses not shown" without naming anyone.
 */
public record BatchRosterResponse(
        List<BatchMemberSummaryResponse> students,
        int hiddenCount
) {
}
