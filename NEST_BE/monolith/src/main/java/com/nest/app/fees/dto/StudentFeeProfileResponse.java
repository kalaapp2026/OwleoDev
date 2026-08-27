package com.nest.app.fees.dto;

import com.nest.app.fees.entity.FeeMode;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;
import java.util.UUID;

/**
 * One student's whole fee position for a period, across every course they are enrolled in.
 *
 * <p>A student can be enrolled in more than one course, so the profile screen has to show which
 * course a payment is being recorded against rather than assuming the one the admin arrived
 * from. The totals here are across all of them, which is what the three stat boxes read.</p>
 */
public record StudentFeeProfileResponse(
        UUID membershipId,
        String studentName,
        String period,
        BigDecimal totalAgreedFee,
        BigDecimal totalPaid,
        BigDecimal totalBalance,
        List<CourseFeeRow> courses
) {

    /**
     * @param batchName  which batch they sit in for this course - context only, since a regular
     *                   fee is keyed by course and period, never by batch.
     * @param lastPaymentId the payment an undo would reverse, or null when there is nothing to
     *                      undo.
     * @param closed     the period was explicitly closed, so any shortfall is written off rather
     *                   than carried forward.
     */
    public record CourseFeeRow(
            UUID courseId,
            String courseName,
            String batchName,
            BigDecimal agreedFee,
            BigDecimal totalPaid,
            BigDecimal balance,
            PaymentStatus status,
            UUID lastPaymentId,
            LocalDate lastPaidOn,
            FeeMode lastPaymentMode,
            boolean closed
    ) {
    }
}
