package com.nest.app.scheduling.controller;

import com.nest.app.scheduling.dto.AddClassInstanceRequest;
import com.nest.app.scheduling.dto.ClassInstanceResponse;
import com.nest.app.scheduling.dto.RescheduleRequest;
import com.nest.app.scheduling.dto.ScheduleResponse;
import com.nest.app.scheduling.dto.SetScheduleRequest;
import com.nest.app.scheduling.service.RescheduleService;
import com.nest.app.scheduling.service.SchedulingService;
import com.nest.common.security.FeatureKey;
import com.nest.common.security.RequiresFeature;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.UUID;

@RestController
@Tag(name = "Scheduling")
public class SchedulingController {

    private final SchedulingService schedulingService;
    private final RescheduleService rescheduleService;

    public SchedulingController(SchedulingService schedulingService, RescheduleService rescheduleService) {
        this.schedulingService = schedulingService;
        this.rescheduleService = rescheduleService;
    }

    @PostMapping("/schedules")
    @RequiresFeature(FeatureKey.BATCH_SCHEDULING)
    public List<ScheduleResponse> setSchedule(@Valid @RequestBody SetScheduleRequest request) {
        return schedulingService.setSchedule(request);
    }

    /** Current weekly pattern (still-open rows only) - the pre-fill source for the Edit batch
     * schedule form, so editing shows what's actually in effect right now. */
    @GetMapping("/batches/{batchId}/schedule")
    public List<ScheduleResponse> currentSchedule(@PathVariable UUID batchId) {
        return schedulingService.currentScheduleForBatch(batchId);
    }

    @GetMapping("/batches/{batchId}/class-instances")
    public List<ClassInstanceResponse> upcoming(@PathVariable UUID batchId) {
        return schedulingService.upcomingForBatch(batchId);
    }

    /** Attendance module's "add a class" - a one-off session not on the weekly schedule. */
    @PostMapping("/batches/{batchId}/class-instances")
    @RequiresFeature(FeatureKey.ATTENDANCE)
    public ClassInstanceResponse addClassInstance(@PathVariable UUID batchId, @Valid @RequestBody AddClassInstanceRequest request) {
        return schedulingService.addAdHocInstance(batchId, request);
    }

    @PostMapping("/class-instances/{id}/reschedule")
    @RequiresFeature(FeatureKey.RESCHEDULE)
    public ClassInstanceResponse reschedule(@PathVariable UUID id, @Valid @RequestBody RescheduleRequest request) {
        return rescheduleService.reschedule(id, request);
    }
}
