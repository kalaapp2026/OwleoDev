package com.nest.app.fees.controller;

import com.nest.app.fees.dto.FeeBalanceResponse;
import com.nest.app.fees.dto.FeeRosterResponse;
import com.nest.app.fees.dto.ReverseFeeEntryRequest;
import com.nest.app.fees.dto.StudentFeeProfileResponse;
import com.nest.app.fees.dto.StudentStatementResponse;
import com.nest.app.fees.entity.FeeCategory;
import com.nest.app.fees.dto.UpdateAgreedFeeRequest;
import com.nest.app.fees.dto.FeeTransactionResponse;
import com.nest.app.fees.dto.RecordFeeEntryRequest;
import com.nest.app.fees.service.FeeSlipService;
import com.nest.app.fees.service.StudentPaymentService;
import com.nest.app.fees.service.FeesService;
import com.nest.app.fees.service.OnlinePaymentService;
import com.nest.common.security.FeatureKey;
import com.nest.common.security.RequiresFeature;
import com.nest.common.security.TenantContext;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.UUID;

@RestController
@Tag(name = "Fees")
public class FeesController {

    private final FeesService feesService;
    private final FeeSlipService feeSlipService;
    private final StudentPaymentService studentPaymentService;
    private final OnlinePaymentService onlinePaymentService;

    public FeesController(FeesService feesService, FeeSlipService feeSlipService,
                          StudentPaymentService studentPaymentService, OnlinePaymentService onlinePaymentService) {
        this.feesService = feesService;
        this.feeSlipService = feeSlipService;
        this.studentPaymentService = studentPaymentService;
        this.onlinePaymentService = onlinePaymentService;
    }

    @PostMapping("/fees/entries")
    @RequiresFeature(FeatureKey.FEES_ENTRY)
    public FeeTransactionResponse recordEntry(@Valid @RequestBody RecordFeeEntryRequest request) {
        return feesService.recordEntry(request);
    }

    /**
     * The whole batch's fee position for a period. One call, so the roster screen doesn't make a
     * balance request per student.
     */
    @GetMapping("/fees/roster")
    @RequiresFeature(FeatureKey.FEES_ENTRY)
    public FeeRosterResponse roster(@RequestParam UUID courseId, @RequestParam UUID batchId,
                                    @RequestParam String period) {
        return feesService.roster(courseId, batchId, period);
    }

    /**
     * Undo a payment. Posts a compensating negative transaction - the ledger is append-only, so
     * there is deliberately no DELETE here and never will be.
     */
    @PostMapping("/fees/entries/{transactionId}/reverse")
    @RequiresFeature(FeatureKey.FEES_ENTRY)
    public FeeTransactionResponse reverseEntry(@PathVariable UUID transactionId,
                                               @RequestBody(required = false) ReverseFeeEntryRequest request) {
        return feesService.reverseEntry(transactionId, request == null ? null : request.reason());
    }

    /**
     * One student's fee position for a period across every course they're enrolled in. The profile
     * screen makes the admin pick which course a payment is for, so it needs the whole set.
     */
    @GetMapping("/students/{membershipId}/fee-profile")
    @RequiresFeature(FeatureKey.FEES_ENTRY)
    public StudentFeeProfileResponse feeProfile(@PathVariable UUID membershipId,
                                                @RequestParam String period) {
        return feesService.feeProfile(membershipId, period);
    }

    /** Change what one student is charged for one course - sibling discount, scholarship, revision. */
    @PatchMapping("/fees/agreed-fee")
    @RequiresFeature(FeatureKey.FEES_ENTRY)
    public FeeBalanceResponse updateAgreedFee(@Valid @RequestBody UpdateAgreedFeeRequest request) {
        return feesService.updateAgreedFee(request);
    }

    /**
     * A student's whole fee history. Optional category filter, mirroring the screen's own chips.
     */
    @GetMapping("/students/{membershipId}/statement")
    @RequiresFeature(FeatureKey.FEES_ENTRY)
    public StudentStatementResponse statement(@PathVariable UUID membershipId,
                                              @RequestParam(required = false) FeeCategory category) {
        return feesService.statement(membershipId, category);
    }

    /** The caller's own statement - no feature needed, since it can only ever be their own. */
    @GetMapping("/me/fees/statement")
    public StudentStatementResponse myStatement(@RequestParam(required = false) FeeCategory category) {
        return feesService.statement(TenantContext.currentMembershipId(), category);
    }

    /**
     * Whether online payment is switched on, and through whom - the app hides "Pay now" when it is
     * not, and picks the checkout to open from {@code provider}.
     */
    @GetMapping("/me/fees/payment-config")
    public java.util.Map<String, Object> paymentConfig() {
        String provider = onlinePaymentService.enabled() ? "RAZORPAY" : studentPaymentService.enabled() ? "MOCK" : "NONE";
        return java.util.Map.of("enabled", !provider.equals("NONE"), "provider", provider);
    }

    /** Starts a Razorpay checkout for the caller's own fee. The amount is the server's, never the client's. */
    @PostMapping("/me/fees/pay/order")
    public com.nest.app.fees.dto.OnlineOrderResponse createOnlineOrder(
            @Valid @RequestBody com.nest.app.fees.dto.PayFeeRequest request) {
        return onlinePaymentService.createOrder(request);
    }

    /** The browser reporting a finished checkout; the signature is checked before anything is settled. */
    @PostMapping("/me/fees/pay/verify")
    public com.nest.app.fees.dto.PayFeeResponse confirmOnlinePayment(
            @Valid @RequestBody com.nest.app.fees.dto.ConfirmOnlinePaymentRequest request) {
        return onlinePaymentService.confirm(request);
    }

    /** The caller paying their own fee. No feature gate: it can only ever settle their own rows. */
    @PostMapping("/me/fees/pay")
    public com.nest.app.fees.dto.PayFeeResponse payOwnFee(
            @Valid @RequestBody com.nest.app.fees.dto.PayFeeRequest request) {
        return studentPaymentService.pay(request);
    }

    @GetMapping("/fees/balance")
    public FeeBalanceResponse getBalance(@RequestParam UUID membershipId, @RequestParam UUID courseId, @RequestParam String period) {
        return feesService.getBalance(membershipId, courseId, period);
    }

}
