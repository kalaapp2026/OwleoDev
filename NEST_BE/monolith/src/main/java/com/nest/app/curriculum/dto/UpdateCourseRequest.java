package com.nest.app.curriculum.dto;

import com.nest.app.curriculum.entity.CourseCategory;
import com.nest.app.curriculum.entity.FeeModel;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;

import java.math.BigDecimal;
import java.util.Set;

/** Editing defaultFee/feePerClass never retroactively changes fees already customised for
 * existing students (PRD 3.3 business rule) - that's enforced simply by CourseMap.agreedFee
 * being copied at enrolment time and never re-derived from Course fee fields afterwards. */
public record UpdateCourseRequest(
        /** Editable: the edit form offers the same category picker as create, and moving a course
         * between disciplines is a legitimate correction. Changing it does not rewrite iconKey -
         * the client sends both, so an icon that no longer belongs to the new category is the
         * client's to resolve rather than something silently reset here. */
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
        String thumbnailUrl,
        @Min(1) @Max(31) Integer billingDayOfMonth,
        @Min(1) @Max(31) Integer dueDayOfMonth,
        Set<@NotBlank String> paymentMethods,
        String iconKey
) {
}
