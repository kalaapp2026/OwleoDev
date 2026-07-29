package com.nest.app.platform.dto;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.UUID;

/**
 * One academy as the Super Admin console sees it: who it is, plus the headline counts that answer
 * "how big is this tenant and is it actually being used".
 *
 * @param lastActivityAt newest last_seen_at across the academy's members - null means nobody has
 *                       opened the app since activity tracking began, which is the honest answer
 *                       rather than pretending it's zero.
 * @param feesCollected  the academy's OWN revenue from its students. Not what the academy owes
 *                       the platform - that's billing, a separate concern.
 */
public record AcademyStatsResponse(
        UUID id,
        String name,
        String city,
        String status,
        String plan,
        Instant createdAt,
        Instant lastActivityAt,
        long students,
        long trainers,
        long admins,
        long courses,
        long batches,
        long events,
        long posts,
        BigDecimal feesCollected
) {}
