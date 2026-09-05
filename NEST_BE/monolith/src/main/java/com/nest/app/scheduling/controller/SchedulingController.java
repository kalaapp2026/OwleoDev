package com.nest.app.scheduling.controller;

import com.nest.app.scheduling.dto.AddClassInstanceRequest;
import com.nest.app.scheduling.dto.CancelClassRequest;
import com.nest.app.scheduling.dto.ClassInstanceResponse;
import com.nest.app.scheduling.dto.RescheduleRequest;
import com.nest.app.scheduling.dto.ScheduleEntryResponse;
import com.nest.app.scheduling.dto.ScheduleResponse;
import com.nest.app.scheduling.dto.SetScheduleRequest;
import com.nest.app.scheduling.dto.SwapInstructorRequest;
import com.nest.app.scheduling.service.RescheduleService;
import com.nest.app.scheduling.service.ScheduleFeedService;
import com.nest.app.scheduling.service.SchedulingService;
import com.nest.common.security.FeatureKey;
import com.nest.common.security.RequiresFeature;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.time.LocalDate;
import java.util.List;
import java.util.UUID;

@RestController
@Tag(name = "Scheduling")
public class SchedulingController {

    private final SchedulingService schedulingService;
    private final RescheduleService rescheduleService;
    private final ScheduleFeedService scheduleFeedService;

    public SchedulingController(SchedulingService schedulingService, RescheduleService rescheduleService,
                                 ScheduleFeedService scheduleFeedService) {
        this.schedulingService = schedulingService;
        this.rescheduleService = rescheduleService;
        this.scheduleFeedService = scheduleFeedService;
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

    /** The Schedule screen's feed - every class in the academy over a window, joined to its
     * batch, course and instructors. Defaults to the next 30 days, matching the screen's own
     * look-ahead. */
    @GetMapping("/schedule/feed")
    public List<ScheduleEntryResponse> feed(
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate from,
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate to,
            @RequestParam(required = false) UUID courseId) {
        LocalDate start = from != null ? from : LocalDate.now();
        LocalDate end = to != null ? to : start.plusDays(30);
        return scheduleFeedService.feed(start, end, courseId);
    }

    @PostMapping("/class-instances/{id}/cancel")
    @RequiresFeature(FeatureKey.RESCHEDULE)
    public ClassInstanceResponse cancel(@PathVariable UUID id, @Valid @RequestBody CancelClassRequest request) {
        return rescheduleService.cancel(id, request.reason());
    }

    @PostMapping("/class-instances/{id}/restore")
    @RequiresFeature(FeatureKey.RESCHEDULE)
    public ClassInstanceResponse restore(@PathVariable UUID id) {
        return rescheduleService.restore(id);
    }

    @PostMapping("/class-instances/{id}/swap-instructor")
    @RequiresFeature(FeatureKey.RESCHEDULE)
    public ClassInstanceResponse swapInstructor(@PathVariable UUID id,
                                                 @Valid @RequestBody SwapInstructorRequest request) {
        return rescheduleService.swapInstructor(id, request.substituteMembershipId(), request.reason());
    }

    @PostMapping("/class-instances/{id}/undo-swap")
    @RequiresFeature(FeatureKey.RESCHEDULE)
    public ClassInstanceResponse undoSwap(@PathVariable UUID id) {
        return rescheduleService.undoSwap(id);
    }

    /** Accepts either half of the reschedule - the client is looking at one row and shouldn't
     * have to work out whether it is the origin or the replacement. */
    @PostMapping("/class-instances/{id}/undo-reschedule")
    @RequiresFeature(FeatureKey.RESCHEDULE)
    public ClassInstanceResponse undoReschedule(@PathVariable UUID id) {
        return rescheduleService.undoReschedule(id);
    }
}
