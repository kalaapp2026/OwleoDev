package com.nest.app.fees.dto;

import java.math.BigDecimal;
import java.util.List;
import java.util.UUID;

/**
 * One batch's fee position for one period, in a single response.
 *
 * <p>The alternative - the roster list plus a {@code /fees/balance} call per student - is 30-plus
 * round trips for a normal batch, on the screen an admin opens most often.</p>
 *
 * <p>The totals are computed over the same rows returned in {@code entries}, so the progress bar
 * and the list can never disagree.</p>
 */
public record FeeRosterResponse(
        UUID courseId,
        UUID batchId,
        String period,
        int studentCount,
        int paidCount,
        BigDecimal expected,
        BigDecimal collected,
        List<FeeRosterEntry> entries
) {

    /**
     * @param lastPaymentId the most recent payment not already reversed, and so the one an "undo"
     *                      would reverse. Null when there is nothing to undo, which is how the UI
     *                      knows to hide the action rather than offer one the server would refuse.
     */
    public record FeeRosterEntry(
            UUID membershipId,
            String studentName,
            BigDecimal agreedFee,
            BigDecimal totalPaid,
            BigDecimal balance,
            PaymentStatus status,
            UUID lastPaymentId
    ) {
    }
}
