package com.nest.app.fees.controller;

import com.nest.app.fees.dto.FeeBalanceResponse;
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
