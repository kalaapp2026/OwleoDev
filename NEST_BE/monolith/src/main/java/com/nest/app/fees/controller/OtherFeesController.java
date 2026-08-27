package com.nest.app.fees.controller;

import com.nest.app.fees.dto.CreateFeeTypeRequest;
import com.nest.app.fees.dto.CreateStudentFeeRequest;
import com.nest.app.fees.dto.FeeRosterResponse;
import com.nest.app.fees.dto.FeeTypeResponse;
import com.nest.app.fees.dto.RecordOtherFeeRequest;
import com.nest.app.fees.service.OtherFeesService;
import com.nest.common.security.FeatureKey;
import com.nest.common.security.RequiresFeature;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.Map;
import java.util.UUID;

/**
 * Costume, exam and annual-day fees, and one-off charges for a single student.
 *
 * <p>Separate from {@link FeesController} because the two halves share only the ledger - a regular
 * fee is billed on a cycle against a course, an Other fee is a one-time charge against a batch.</p>
 */
@RestController
@Tag(name = "Other Fees")
public class OtherFeesController {

    private final OtherFeesService otherFeesService;

    public OtherFeesController(OtherFeesService otherFeesService) {
        this.otherFeesService = otherFeesService;
    }

    @GetMapping("/fees/other/types")
    @RequiresFeature(FeatureKey.FEES_ENTRY)
    public List<FeeTypeResponse> listTypes(
            @RequestParam(defaultValue = "false") boolean includeRetired) {
        return otherFeesService.listFeeTypes(includeRetired);
    }

    @PostMapping("/fees/other/types")
    @RequiresFeature(FeatureKey.FEES_ENTRY)
    public FeeTypeResponse createType(@Valid @RequestBody CreateFeeTypeRequest request) {
        return otherFeesService.createFeeType(request);
    }

    /** Everyone in a batch and where they stand on one fee type. */
    @GetMapping("/fees/other/roster")
    @RequiresFeature(FeatureKey.FEES_ENTRY)
    public FeeRosterResponse roster(@RequestParam UUID feeTypeId, @RequestParam UUID batchId) {
        return otherFeesService.roster(feeTypeId, batchId);
    }

    @PostMapping("/fees/other/entries")
    @RequiresFeature(FeatureKey.FEES_ENTRY)
    public Map<String, UUID> recordPayment(@Valid @RequestBody RecordOtherFeeRequest request) {
        return Map.of("transactionId", otherFeesService.recordPayment(request));
    }

    /** A one-off charge for a single student, not the batch. */
    @PostMapping("/fees/other/student-fees")
    @RequiresFeature(FeatureKey.FEES_ENTRY)
    public Map<String, UUID> createStudentFee(@Valid @RequestBody CreateStudentFeeRequest request) {
        return Map.of("studentFeeId", otherFeesService.createStudentFee(request));
    }
}
