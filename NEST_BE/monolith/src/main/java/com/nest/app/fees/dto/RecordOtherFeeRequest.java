package com.nest.app.fees.dto;

import com.nest.app.fees.entity.FeeMode;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.NotNull;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.UUID;

/**
 * A payment against an Other fee - either a shared fee type or a per-student one-off.
 *
 * <p>Exactly one of {@code feeTypeId} and {@code studentFeeId} must be set; the service rejects
 * both-or-neither before the database's own check constraint would.</p>
 */
public record RecordOtherFeeRequest(
        @NotNull UUID membershipId,
        UUID feeTypeId,
        UUID studentFeeId,
        @NotNull @DecimalMin(value = "0", inclusive = false) BigDecimal amountPaid,
        @NotNull FeeMode mode,
        String gatewayRef,
        String note,
        LocalDate receivedOn
) {
}
