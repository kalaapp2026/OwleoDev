package com.nest.app.enrolment.dto;

import jakarta.validation.constraints.NotNull;

import java.math.BigDecimal;
import java.util.UUID;

/** fee == null means "use the course's default fee" (PRD 3.4: fee auto-fills, editable per student). */
public record CourseFeeSelection(@NotNull UUID courseId, BigDecimal fee) {
}
