package com.nest.app.curriculum.dto;

import com.nest.app.curriculum.entity.CourseCategory;
import com.nest.app.curriculum.entity.FeeCycle;
import com.nest.app.curriculum.entity.FeeModel;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;

import java.math.BigDecimal;

/** Which of feePerClass / defaultFee+hybrid* is actually required depends on feeModel -
 * CourseService validates that combination (see CourseService.validateFeeModelFields). */
public record CreateCourseRequest(
        @NotNull CourseCategory category,
        @NotBlank String name,
        String description,
        String durationLevel,
        @NotNull FeeModel feeModel,
        @DecimalMin("0.0") BigDecimal defaultFee,
        @DecimalMin("0.0") BigDecimal feePerClass,
        Integer hybridExpectedClassesPerPeriod,
        Integer hybridThresholdAttendance,
        Integer hybridFeeAboveThresholdPercent,
        Integer hybridFeeBelowThresholdPercent,
        @DecimalMin("0.0") BigDecimal hybridMinFeeAmount,
        @NotNull FeeCycle feeCycle,
        String thumbnailUrl,
        /** Day of month fee slips auto-generate on for this course; null disables auto-billing. */
        @Min(1) @Max(31) Integer billingDayOfMonth
) {
}
