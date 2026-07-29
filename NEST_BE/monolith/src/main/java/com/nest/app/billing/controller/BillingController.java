package com.nest.app.billing.controller;

import com.nest.app.billing.dto.BillingDtos;
import com.nest.app.billing.service.BillingService;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.time.YearMonth;
import java.util.List;
import java.util.Map;
import java.util.UUID;

/**
 * Platform billing console - SUPER_ADMIN only. This is the one area where the console genuinely
 * writes: plan and payment state is the platform operator's own record, not the academy's, so
 * editing it here doesn't undermine anyone else's audit trail (unlike the academy's student/fee
 * data, which stays read-only).
 */
@RestController
@Tag(name = "Billing (Super Admin)")
@PreAuthorize("hasRole('SUPER_ADMIN')")
public class BillingController {

    private final BillingService billingService;

    public BillingController(BillingService billingService) {
        this.billingService = billingService;
    }

    @GetMapping("/admin/billing/summary")
    public BillingDtos.BillingSummaryResponse summary() {
        return billingService.summary();
    }

    @GetMapping("/admin/billing/plans")
    public List<BillingDtos.PlanResponse> plans() {
        return billingService.plans();
    }

    /** Defaults to the current month, which is what the console opens on. */
    @GetMapping("/admin/billing/invoices")
    public List<BillingDtos.InvoiceResponse> invoices(@RequestParam(required = false) String period) {
        return billingService.invoicesForPeriod(period == null ? YearMonth.now().toString() : period);
    }

    @GetMapping("/admin/billing/invoices/overdue")
    public List<BillingDtos.InvoiceResponse> overdue() {
        return billingService.overdueInvoices();
    }

    @GetMapping("/admin/billing/academies/{academyId}/invoices")
    public List<BillingDtos.InvoiceResponse> forAcademy(@PathVariable UUID academyId) {
        return billingService.invoicesForAcademy(academyId);
    }

    /** Safe to call repeatedly - idempotent per (academy, period), so a retry can't double-charge. */
    @PostMapping("/admin/billing/invoices/generate")
    public Map<String, Object> generate(@RequestParam(required = false) String period) {
        String target = period == null ? YearMonth.now().toString() : period;
        return Map.of("period", target, "created", billingService.generateInvoices(target));
    }

    @PostMapping("/admin/billing/invoices/{invoiceId}/pay")
    public BillingDtos.InvoiceResponse markPaid(@PathVariable UUID invoiceId,
                                                @Valid @RequestBody BillingDtos.MarkPaidRequest request) {
        return billingService.markPaid(invoiceId, request);
    }

    @PostMapping("/admin/billing/invoices/{invoiceId}/waive")
    public BillingDtos.InvoiceResponse waive(@PathVariable UUID invoiceId,
                                             @RequestParam(required = false) String note) {
        return billingService.waive(invoiceId, note);
    }

    @PutMapping("/admin/billing/academies/{academyId}/plan")
    public void changePlan(@PathVariable UUID academyId,
                           @Valid @RequestBody BillingDtos.ChangePlanRequest request) {
        billingService.changePlan(academyId, request.planCode());
    }
}
