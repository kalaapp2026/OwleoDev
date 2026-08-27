package com.nest.app.fees.dto;

import com.nest.app.fees.entity.FeeMode;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;
import java.util.UUID;

/**
 * A named charge an academy raises outside the regular course fee.
 *
 * <p>{@code batches} carries names as well as ids because the selector shows them, and a second
 * round trip to resolve a handful of names on every list is not worth the tidiness.</p>
 */
public record FeeTypeResponse(
        UUID id,
        String name,
        BigDecimal amount,
        LocalDate dueDate,
        FeeMode defaultMode,
        boolean active,
        List<BatchBinding> batches
) {
    public record BatchBinding(UUID batchId, String batchName, UUID courseId, String courseName) {
    }
}
