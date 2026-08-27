package com.nest.app.fees.dto;

import com.nest.app.fees.entity.FeeMode;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.UUID;

/**
 * A one-off charge for a single named student - a replacement book, an extra costume.
 *
 * <p>Deliberately not a fee type with one batch: this belongs to a person, not a group, and
 * modelling it as a group of one would make it show up in every batch-level total.</p>
 */
public record CreateStudentFeeRequest(
        @NotNull UUID membershipId,
        @NotNull @Size(min = 2, max = 120) String name,
        @NotNull @DecimalMin(value = "0", inclusive = false) BigDecimal amount,
        LocalDate dueDate,
        FeeMode defaultMode,
        String note
) {
}
