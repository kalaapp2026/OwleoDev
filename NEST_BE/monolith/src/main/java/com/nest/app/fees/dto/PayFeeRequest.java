package com.nest.app.fees.dto;

import com.nest.app.fees.entity.FeeCategory;
import jakarta.validation.constraints.NotNull;

import java.util.UUID;

/** Which fee the caller is paying. There is deliberately NO amount: the server works out what is
 * owed from the ledger, so a client cannot pay a fee off for less. */
public record PayFeeRequest(
        @NotNull FeeCategory category,
        UUID courseId,
        String period,
        UUID feeTypeId,
        UUID studentFeeId,
        String method
) {
}
