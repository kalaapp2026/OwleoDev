package com.nest.app.enrolment.dto;

import java.util.Map;
import java.util.Set;
import java.util.UUID;

public record TrainerResponse(
        UUID userId,
        UUID membershipId,
        String username,
        /** The generated temp password for a brand-new account. Null when no account was created -
         * i.e. an existing NEST user was linked to this academy, so they keep their own password. */
        String temporaryPassword,
        /** courseId -> features granted on that course (the per-course checklist that was saved). */
        Map<UUID, Set<String>> courseFeatures,
        /** True when this linked an EXISTING NEST user (someone already studying or teaching
         * elsewhere) to this academy. The membership is PENDING_CONFIRMATION and grants nothing
         * until that person approves it with the code sent to them (PRD 7.4). */
        boolean pendingConfirmation
) {
}
