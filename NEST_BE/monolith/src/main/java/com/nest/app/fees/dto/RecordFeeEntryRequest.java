package com.nest.app.fees.dto;

import com.nest.app.fees.entity.FeeMode;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;

import java.math.BigDecimal;
import java.util.UUID;

/** closePeriod is the "Close" choice on a partial payment - "remaining amount should not carry
 * forward to next month" - vs the default (false/null), which leaves the period OPEN so any
 * shortfall rolls into the next fee slip generated for it ("partial pay" in the PRD wording). */
public record RecordFeeEntryRequest(
        @NotNull UUID membershipId,
        @NotNull UUID courseId,
        @NotBlank String period,
        @NotNull @DecimalMin("0.01") BigDecimal amountPaid,
        @NotNull FeeMode mode,
        String note,
        String gatewayRef,
        Boolean closePeriod
) {
}
