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
import java.util.Set;

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
        @Min(1) @Max(31) Integer billingDayOfMonth,
        /** Day of month an unpaid slip flips to overdue. Normally a few days after
         * billingDayOfMonth; null means nothing is ever auto-marked overdue. */
        @Min(1) @Max(31) Integer dueDayOfMonth,
        /** Any of CASH / UPI / GATEWAY. Empty or null defaults to cash only, so a course created
         * through an older client still has a usable method rather than none. */
        Set<@NotBlank String> paymentMethods,
        /** Key into the app's icon set. Unset falls back to the category's general icon. */
        String iconKey
) {
}
