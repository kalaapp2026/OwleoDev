package com.nest.app.enrolment.controller;

import com.nest.app.enrolment.dto.BatchMemberSummaryResponse;
import com.nest.app.enrolment.dto.BatchResponse;
import com.nest.app.enrolment.dto.CreateBatchRequest;
import com.nest.app.enrolment.dto.UpdateBatchRequest;
import com.nest.app.enrolment.entity.BatchStatus;
import com.nest.app.enrolment.service.BatchService;
import com.nest.common.security.FeatureKey;
import com.nest.common.security.RequiresFeature;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.UUID;

@RestController
@Tag(name = "Batches")
public class BatchController {

    private final BatchService batchService;

    public BatchController(BatchService batchService) {
        this.batchService = batchService;
    }

    @PostMapping("/batches")
    @RequiresFeature(FeatureKey.BATCH_CREATION)
    public BatchResponse create(@Valid @RequestBody CreateBatchRequest request) {
        return batchService.create(request);
    }

    @PutMapping("/batches/{id}")
    @RequiresFeature(FeatureKey.BATCH_CREATION)
    public BatchResponse update(@PathVariable UUID id, @Valid @RequestBody UpdateBatchRequest request) {
        return batchService.update(id, request);
    }

    @PatchMapping("/batches/{id}/status")
    @RequiresFeature(FeatureKey.BATCH_CREATION)
    public BatchResponse setStatus(@PathVariable UUID id, @RequestParam BatchStatus status) {
        return batchService.setStatus(id, status);
    }

    @GetMapping("/batches/{id}")
    public BatchResponse get(@PathVariable UUID id) {
        return batchService.get(id);
    }

    @GetMapping("/courses/{courseId}/batches")
    public List<BatchResponse> listForCourse(@PathVariable UUID courseId) {
        return batchService.listForCourse(courseId);
    }

    /** Every batch in the active academy - the batch list screen, which is organised by batch
     * rather than drilled into course by course. Distinct path from the membership-scoped
     * {@code /batches} below, which answers a different question. */
    @GetMapping("/batches/all")
    @RequiresFeature(FeatureKey.BATCH_CREATION)
    public List<BatchResponse> listAll() {
        return batchService.listForActiveAcademy();
    }

    /** A Student's "my batches" view - just the batch(es) this one membership actually belongs
     * to, across every course, never a course's full batch list (which may include batches other
     * students are in). */
    @GetMapping("/batches")
    public List<BatchResponse> listForMembership(@RequestParam UUID membershipId) {
        return batchService.listForMembership(membershipId);
    }

    @PostMapping("/batches/{id}/members")
    @RequiresFeature(FeatureKey.BATCH_CREATION)
    public void addMember(@PathVariable UUID id, @RequestParam UUID membershipId) {
        batchService.addMember(id, membershipId);
    }

    @GetMapping("/batches/{id}/members")
    public List<UUID> listMembers(@PathVariable UUID id) {
        return batchService.listMemberIds(id);
    }

    /** Attendance marking's roster source - a real name and photo per student instead of a bare
     * membership UUID. */
    @GetMapping("/batches/{id}/members/summary")
    public List<BatchMemberSummaryResponse> listMemberSummaries(@PathVariable UUID id) {
        return batchService.listMemberSummaries(id);
    }

    @DeleteMapping("/batches/{id}/members")
    @RequiresFeature(FeatureKey.BATCH_CREATION)
    public void removeMember(@PathVariable UUID id, @RequestParam UUID membershipId) {
        batchService.removeMember(id, membershipId);
    }

    @DeleteMapping("/batches/{id}")
    @RequiresFeature(FeatureKey.BATCH_CREATION)
    public void delete(@PathVariable UUID id) {
        batchService.delete(id);
    }
}
