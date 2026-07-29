package com.nest.app.billing.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Positive;

import java.math.BigDecimal;
import java.time.Instant;
import java.time.LocalDate;
import java.util.List;
import java.util.UUID;

/** Request/response shapes for the Super Admin billing console, grouped since they're small and
 * only ever used together. */
public final class BillingDtos {

    private BillingDtos() {
    }

    public record PlanResponse(String code, String displayName, BigDecimal monthlyPrice,
                               Integer maxStudents, Integer maxTrainers, boolean active) {}

    /**
     * @param overdue      derived from {@code dueOn} rather than stored, so it can't go stale.
     * @param daysOverdue  0 unless overdue - drives the "how bad is this" ordering in the console.
     */
    public record InvoiceResponse(UUID id, UUID academyId, String academyName, String period,
                                  String planCode, BigDecimal amount, String status,
                                  LocalDate issuedOn, LocalDate dueOn, boolean overdue, long daysOverdue,
                                  Instant paidAt, BigDecimal paidAmount, String paymentMethod,
                                  String paymentRef, String note) {}

    /**
     * @param mrr            monthly recurring revenue - the sum of every ACTIVE academy's plan
     *                       price. Forward-looking (what a normal month should bill), which is why
     *                       it isn't the same as {@code billedThisMonth}.
     * @param billedThisMonth what was actually invoiced this period, including any academy that
     *                       changed plan mid-month or was onboarded late.
     */
    public record BillingSummaryResponse(BigDecimal mrr, BigDecimal arr,
                                         BigDecimal billedThisMonth, BigDecimal collectedThisMonth,
                                         BigDecimal outstanding, long overdueCount,
                                         long payingAcademies, long freeAcademies,
                                         String currentPeriod, List<PlanBreakdown> byPlan) {}

    public record PlanBreakdown(String planCode, String displayName, long academies, BigDecimal monthlyValue) {}

    public record MarkPaidRequest(
            @Positive BigDecimal amount,
            @NotBlank String method,
            String reference,
            String note
    ) {}

    public record ChangePlanRequest(@NotBlank String planCode) {}
}
