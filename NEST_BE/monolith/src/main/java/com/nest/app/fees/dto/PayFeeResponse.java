package com.nest.app.fees.dto;

import java.math.BigDecimal;
import java.util.UUID;

public record PayFeeResponse(UUID transactionId, BigDecimal amount, String gatewayRef) {
}
