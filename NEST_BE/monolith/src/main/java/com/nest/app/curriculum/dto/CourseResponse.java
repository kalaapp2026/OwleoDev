package com.nest.app.curriculum.dto;

import com.nest.app.curriculum.entity.CourseCategory;
import com.nest.app.curriculum.entity.CourseStatus;
import com.nest.app.curriculum.entity.FeeCycle;
import com.nest.app.curriculum.entity.FeeModel;

import java.math.BigDecimal;
import java.util.Set;
import java.util.UUID;

public record CourseResponse(
        UUID id,
        UUID academyId,
        CourseCategory category,
        String name,
        String description,
        String durationLevel,
        FeeModel feeModel,
        BigDecimal defaultFee,
        BigDecimal feePerClass,
        Integer hybridExpectedClassesPerPeriod,
        Integer hybridThresholdAttendance,
        Integer hybridFeeAboveThresholdPercent,
        Integer hybridFeeBelowThresholdPercent,
        BigDecimal hybridMinFeeAmount,
        FeeCycle feeCycle,
        String thumbnailUrl,
        CourseStatus status,
        Integer billingDayOfMonth,
        Integer dueDayOfMonth,
        /** Expanded from the stored comma-separated column so clients get a real array. */
        Set<String> paymentMethods,
        String iconKey
) {
}
