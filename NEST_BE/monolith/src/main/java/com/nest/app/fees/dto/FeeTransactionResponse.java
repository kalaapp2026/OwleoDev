package com.nest.app.fees.dto;

import com.nest.app.fees.entity.FeeMode;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.UUID;

public record FeeTransactionResponse(
        UUID id, UUID membershipId, UUID courseId, String period, BigDecimal amountPaid,
        FeeMode mode, String note, UUID recordedBy, String gatewayRef, Instant createdAt
) {
}
