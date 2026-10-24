package com.nest.app.fees.dto;

import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.NotNull;

import java.math.BigDecimal;
import java.util.UUID;

/**
 * Change what ONE student owes for one Other fee. Exactly one of {@code feeTypeId} (a shared fee -
 * only this student's amount moves) and {@code studentFeeId} (their own one-off - the fee itself
 * moves) is set.
 */
public record UpdateOtherAmountRequest(
        @NotNull UUID membershipId,
        UUID feeTypeId,
        UUID studentFeeId,
        @NotNull @DecimalMin(value = "0", inclusive = false) BigDecimal amount
) {
}
