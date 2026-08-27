package com.nest.app.fees.dto;

import com.nest.app.fees.entity.FeeMode;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;
import java.util.UUID;

/**
 * Create a shared "Other" fee - costume, exam, annual day.
 *
 * <p>At least one batch is required. A fee type bound to nothing applies to nobody, so it would
 * sit in the catalogue looking real while quietly charging no one.</p>
 */
public record CreateFeeTypeRequest(
        @NotNull @Size(min = 2, max = 120) String name,
        @NotNull @DecimalMin(value = "0", inclusive = false) BigDecimal amount,
        @NotEmpty List<UUID> batchIds,
        LocalDate dueDate,
        FeeMode defaultMode
) {
}
