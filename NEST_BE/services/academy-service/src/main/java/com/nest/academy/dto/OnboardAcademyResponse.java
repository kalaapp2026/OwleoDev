package com.nest.academy.dto;

/**
 * temporaryPassword is surfaced here for Phase 1 only so the caller can relay it manually - once
 * notification-service exists (Phase 4) this should be delivered via email/SMS from a
 * credentials.issued Kafka event instead of a synchronous API response (PRD 3.2: "credentials are
 * emailed/SMS'd automatically").
 */
public record OnboardAcademyResponse(
        AcademyResponse academy,
        String adminUsername,
        String adminTemporaryPassword
) {
}
