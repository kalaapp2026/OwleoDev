package com.nest.app.fees.dto;

import com.nest.app.fees.entity.FeeSlipStatus;

import java.math.BigDecimal;
import java.time.Instant;
import java.time.LocalDate;
import java.util.UUID;

public record FeeSlipResponse(
        UUID id,
        UUID membershipId,
        UUID courseId,
        String period,
        LocalDate billingPeriodStart,
        LocalDate billingPeriodEnd,
        BigDecimal amountDue,
        BigDecimal carriedForwardAmount,
        FeeSlipStatus status,
        Integer classesHeld,
        Integer classesAttended,
        Instant generatedAt
) {
}
