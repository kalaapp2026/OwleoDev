package com.nest.app.fees.dto;

import com.nest.app.fees.entity.FeeMode;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;
import java.util.UUID;

/**
 * Every Other fee that applies to one student: the shared fee types their batches are bound to,
 * plus any one-off charges raised against them personally.
 *
 * <p>Returned even when it is empty. A student with no Other record still needs a screen to open,
 * or an admin has nowhere to add their first one-off fee from.</p>
 */
public record StudentOtherFeesResponse(
        UUID membershipId,
        String studentName,
        BigDecimal totalAmount,
        BigDecimal totalPaid,
        BigDecimal outstanding,
        List<OtherFeeRow> fees
) {

    /**
     * @param feeTypeId    set for a shared catalogue fee; null for a one-off.
     * @param studentFeeId set for a one-off raised against this student; null for a shared fee.
     * @param custom       true for the one-off case, so the UI can label it "Individual fee"
     *                     without inspecting which id happens to be null.
     */
    public record OtherFeeRow(
            UUID feeTypeId,
            UUID studentFeeId,
            String name,
            BigDecimal amount,
            BigDecimal paid,
            BigDecimal balance,
            PaymentStatus status,
            LocalDate dueDate,
            LocalDate lastPaidOn,
            FeeMode lastPaymentMode,
            UUID lastPaymentId,
            boolean custom
    ) {
    }
}
