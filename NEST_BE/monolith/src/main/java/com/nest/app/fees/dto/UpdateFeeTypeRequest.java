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
 * Edit a shared Other fee in place. Everything is replaced as sent - the form always carries the
 * whole fee - so a null {@code dueDate} clears the last date to pay rather than leaving it alone.
 */
public record UpdateFeeTypeRequest(
        @NotNull @Size(min = 2, max = 120) String name,
        @NotNull @DecimalMin(value = "0", inclusive = false) BigDecimal amount,
        @NotEmpty List<UUID> batchIds,
        LocalDate dueDate,
        List<FeeMode> paymentMethods
) {
}
