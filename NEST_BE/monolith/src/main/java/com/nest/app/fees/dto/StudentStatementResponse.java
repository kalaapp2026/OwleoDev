package com.nest.app.fees.dto;

import com.nest.app.fees.entity.FeeCategory;
import com.nest.app.fees.entity.FeeMode;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;
import java.util.UUID;

/**
 * A student's whole fee history - every period of every course, plus (once Other Fees lands) their
 * one-off charges, in one list.
 *
 * <p>Rows are per period rather than per transaction. A month paid in three instalments is one
 * line on a statement, not three - the instalments are how the money arrived, which the ledger
 * records, but not what the family is being told they owed.</p>
 */
public record StudentStatementResponse(
        UUID membershipId,
        String studentName,
        BigDecimal totalBilled,
        BigDecimal totalPaid,
        BigDecimal outstanding,
        List<StatementRow> rows
) {

    /**
     * @param label   the period ("2026-08") for a regular fee, or the fee's name for an Other one.
     * @param context which course or batch it belongs to, shown under the label.
     * @param paidOn  the most recent payment against this row, which is what it gets grouped by.
     */
    public record StatementRow(
            String label,
            FeeCategory category,
            String context,
            BigDecimal fee,
            BigDecimal paid,
            PaymentStatus status,
            LocalDate paidOn,
            FeeMode mode
    ) {
    }
}
