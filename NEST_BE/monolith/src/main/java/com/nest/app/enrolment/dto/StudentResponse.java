package com.nest.app.enrolment.dto;

import java.math.BigDecimal;
import java.util.Map;
import java.util.UUID;

public record StudentResponse(
        UUID userId,
        UUID membershipId,
        String username,
        String fullName,
        Map<UUID, BigDecimal> courseFees,
        /** True when this call linked an EXISTING NEST user to a new academy - the membership is
         * PENDING_CONFIRMATION and won't grant access until confirmMembership() succeeds (PRD 7.4). */
        boolean pendingConfirmation
) {
}
