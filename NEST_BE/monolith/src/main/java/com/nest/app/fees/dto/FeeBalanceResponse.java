package com.nest.app.fees.dto;

import java.math.BigDecimal;
import java.util.UUID;

public record FeeBalanceResponse(
        UUID membershipId, UUID courseId, String period,
        BigDecimal agreedFee, BigDecimal totalPaid, BigDecimal balance,
        boolean closed
) {
}
