package com.nest.app.fees.dto;

import java.math.BigDecimal;

/**
 * The fees landing aggregate: where each category stands right now.
 *
 * <p>Both halves are computed over the same filters, so the two cards are always comparable.</p>
 */
public record FeeSummaryResponse(
        CategorySummary regular,
        CategorySummary other
) {

    /**
     * @param paidCount      students who owe nothing further on this category.
     * @param totalCount     students the category applies to at all.
     * @param expected       what should be collected.
     * @param collected      what has been, net of reversals.
     * @param manualAmount   taken by hand - cash or UPI. Grouped because the question they answer
     *                       is the same: is it in the cash box rather than the gateway statement.
     * @param gatewayAmount  taken through the payment gateway.
     * @param pending        expected less collected, floored at zero - an overpaid batch must not
     *                       show a negative amount still to collect.
     */
    public record CategorySummary(
            int paidCount,
            int totalCount,
            BigDecimal expected,
            BigDecimal collected,
            BigDecimal manualAmount,
            BigDecimal gatewayAmount,
            BigDecimal pending
    ) {
        public static CategorySummary empty() {
            return new CategorySummary(0, 0, BigDecimal.ZERO, BigDecimal.ZERO,
                    BigDecimal.ZERO, BigDecimal.ZERO, BigDecimal.ZERO);
        }
    }
}
