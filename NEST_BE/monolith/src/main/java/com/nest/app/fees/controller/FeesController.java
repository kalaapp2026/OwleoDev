package com.nest.app.fees.controller;

import com.nest.app.fees.dto.FeeBalanceResponse;
import com.nest.app.fees.dto.FeeRosterResponse;
import com.nest.app.fees.dto.ReverseFeeEntryRequest;
import com.nest.app.fees.dto.StudentFeeProfileResponse;
import com.nest.app.fees.dto.StudentStatementResponse;
import com.nest.app.fees.entity.FeeCategory;
import com.nest.app.fees.dto.UpdateAgreedFeeRequest;
import com.nest.app.fees.dto.FeeSlipResponse;
import com.nest.app.fees.dto.FeeTransactionResponse;
import com.nest.app.fees.dto.RecordFeeEntryRequest;
import com.nest.app.fees.service.FeeSlipService;
import com.nest.app.fees.service.FeesService;
import com.nest.common.security.FeatureKey;
import com.nest.common.security.RequiresFeature;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.UUID;

@RestController
@Tag(name = "Fees")
public class FeesController {

    private final FeesService feesService;
    private final FeeSlipService feeSlipService;

    public FeesController(FeesService feesService, FeeSlipService feeSlipService) {
        this.feesService = feesService;
        this.feeSlipService = feeSlipService;
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

    /**
     * The statement as a CSV download. Takes the same category filter as the screen, so the file
     * is exactly what the reader was looking at rather than silently widening to everything.
     */
    @GetMapping("/students/{membershipId}/statement/report")
    @RequiresFeature(FeatureKey.FEES_ENTRY)
    public ResponseEntity<byte[]> statementReport(@PathVariable UUID membershipId,
                                                  @RequestParam(required = false) FeeCategory category) {
        byte[] csv = feesService.generateStatementCsv(membershipId, category)
                .getBytes(StandardCharsets.UTF_8);
        return ResponseEntity.ok()
                .header(HttpHeaders.CONTENT_DISPOSITION, "attachment; filename=fee-statement.csv")
                .contentType(MediaType.parseMediaType("text/csv"))
                .body(csv);
    }

    @GetMapping("/fees/balance")
    public FeeBalanceResponse getBalance(@RequestParam UUID membershipId, @RequestParam UUID courseId, @RequestParam String period) {
        return feesService.getBalance(membershipId, courseId, period);
    }

    @GetMapping("/students/{membershipId}/fees")
    public List<FeeTransactionResponse> history(@PathVariable UUID membershipId) {
        return feesService.historyForStudent(membershipId);
    }

    @GetMapping("/fees/dashboard")
    @RequiresFeature(FeatureKey.FEES_DASHBOARD)
    public java.math.BigDecimal dashboardCollected(@RequestParam UUID courseId, @RequestParam String period) {
        return feesService.collectedForCourseAndPeriod(courseId, period);
    }

    /** Manual "generate now" trigger for a course's fee slips - same calculation the daily cron
     * runs, exposed for testing and for catching up a course whose billing day already passed
     * this month. Gated by FEES_ENTRY, same access level as recording a payment. */
    @PostMapping("/courses/{courseId}/fee-slips/generate")
    @RequiresFeature(FeatureKey.FEES_ENTRY)
    public List<FeeSlipResponse> generateFeeSlips(@PathVariable UUID courseId) {
        return feeSlipService.generateNow(courseId);
    }

    @GetMapping("/students/{membershipId}/fee-slips")
    public List<FeeSlipResponse> feeSlipHistory(@PathVariable UUID membershipId) {
        return feeSlipService.historyForStudent(membershipId);
    }

    /** The download button: a CSV of every student mapped to this course for this period - what
     * they owe, what they've paid, and the course's own billing cycle. Gated the same as the
     * existing Fees Dashboard aggregate. */
    @GetMapping("/fees/report")
    @RequiresFeature(FeatureKey.FEES_DASHBOARD)
    public ResponseEntity<byte[]> downloadReport(@RequestParam UUID courseId, @RequestParam String period) {
        byte[] csv = feesService.generateCourseReport(courseId, period).getBytes(StandardCharsets.UTF_8);
        return ResponseEntity.ok()
                .header(HttpHeaders.CONTENT_DISPOSITION, "attachment; filename=fees-report-" + period + ".csv")
                .contentType(MediaType.parseMediaType("text/csv"))
                .body(csv);
    }
}
