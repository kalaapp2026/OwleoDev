package com.nest.app.scheduling.dto;

import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.NotNull;

import java.time.LocalDate;
import java.util.List;
import java.util.UUID;

public record SetScheduleRequest(
        @NotNull UUID batchId,
        @NotEmpty List<SlotRequest> slots,
        @NotNull LocalDate effectiveFrom
) {
}
