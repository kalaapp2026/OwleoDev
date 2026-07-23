package com.nest.common.audit;

import java.time.Instant;
import java.util.UUID;

/**
 * Who/when/what record for the "audit log table for every fee entry, reschedule, feature-grant
 * change, and membership-link request" requirement (PRD 4.6). Each service persists these in its
 * own audit_log table (database-per-service) and may additionally publish to a
 * {@code audit.events} Kafka topic for centralised, cross-service audit search later.
 */
public record AuditEvent(
        Instant timestamp,
        UUID actorUserId,
        UUID actorMembershipId,
        String action,
        String entityType,
        String entityId,
        String serviceName,
        String detail
) {
}
