package com.nest.app.fees.dto;

import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.NotNull;

import java.math.BigDecimal;
import java.util.UUID;

/**
 * Change what one student is charged for one course - a sibling discount, a scholarship, a
 * mid-year revision.
 *
 * <p>Zero is allowed. A student on a full scholarship is charged nothing, which is different from
 * having no fee record at all.</p>
 */
public record UpdateAgreedFeeRequest(
        @NotNull UUID membershipId,
        @NotNull UUID courseId,
        @NotNull @DecimalMin("0") BigDecimal agreedFee
) {
}
