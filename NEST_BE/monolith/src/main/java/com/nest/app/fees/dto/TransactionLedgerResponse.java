package com.nest.app.fees.dto;

import com.nest.app.fees.entity.FeeCategory;
import com.nest.app.fees.entity.FeeMode;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;
import java.util.UUID;

/**
 * Every payment an academy took in a date range, across both fee categories.
 *
 * <p>Reversals are included rather than filtered out. This is the view an admin opens to answer
 * "what did we take last month" and to check someone else's entries - a document that quietly
 * omits the undone ones would make the totals unexplainable, since the totals are net.</p>
 */
public record TransactionLedgerResponse(
        BigDecimal regularTotal,
        BigDecimal otherTotal,
        BigDecimal total,
        List<LedgerEntry> entries
) {

    /**
     * @param context   the course or the fee type - what the money was for.
     * @param reversal  true for a compensating row. Its amount is negative, and the UI shows it as
     *                  a reversal rather than a payment.
     */
    public record LedgerEntry(
            UUID transactionId,
            UUID membershipId,
            String studentName,
            FeeCategory category,
            String context,
            BigDecimal amount,
            FeeMode mode,
            LocalDate occurredOn,
            boolean reversal
    ) {
    }
}
