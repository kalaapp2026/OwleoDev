package com.nest.app.scheduling.service;

import com.nest.app.scheduling.dto.AddClassInstanceRequest;
import com.nest.app.scheduling.dto.ClassInstanceResponse;
import com.nest.app.scheduling.dto.ScheduleResponse;
import com.nest.app.scheduling.dto.SetScheduleRequest;
import com.nest.app.scheduling.dto.SlotRequest;
import com.nest.app.scheduling.entity.ClassInstance;
import com.nest.app.scheduling.entity.ClassInstanceStatus;
import com.nest.app.scheduling.entity.Schedule;
import com.nest.app.scheduling.repository.ClassInstanceRepository;
import com.nest.app.scheduling.repository.ScheduleRepository;
import com.nest.common.audit.Auditable;
import com.nest.common.exception.ConflictException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;

/**
 * PRD 3.7.1. Setting a recurring schedule also materialises the next several weeks of
 * {@link ClassInstance} rows immediately (rather than deferring to a background job), so the
 * worked example in the PRD - "the moment this is saved, every checked-in student's Calendar
 * shows two weekly recurring class entries" - is true right away. A real background job to keep
 * extending the rolling window is Phase 7 polish, not modelled here.
 */
@Service
public class SchedulingService {

    private static final int MATERIALISE_WEEKS_AHEAD = 8;

    private final ScheduleRepository scheduleRepository;
    private final ClassInstanceRepository classInstanceRepository;

    public SchedulingService(ScheduleRepository scheduleRepository, ClassInstanceRepository classInstanceRepository) {
        this.scheduleRepository = scheduleRepository;
        this.classInstanceRepository = classInstanceRepository;
    }

    /**
     * Also the mechanism for CHANGING an existing batch's schedule (not just setting one for the
     * first time): any still-open schedule rows for this batch are closed out as of the day
     * before the new pattern starts, and their not-yet-held future instances are cancelled - the
     * old timing stops applying and the new one "continues from here on", while everything before
     * the change date (including any classes already HELD) is left untouched for audit/history.
     */
    @Transactional
    @Auditable(action = "SCHEDULE_SET", entityType = "schedule")
    public List<ScheduleResponse> setSchedule(SetScheduleRequest request) {
        supersedeExistingSchedule(request.batchId(), request.effectiveFrom());

        List<Schedule> saved = new ArrayList<>();
        for (SlotRequest slot : request.slots()) {
            Schedule schedule = scheduleRepository.save(Schedule.builder()
                    .batchId(request.batchId())
                    .dayOfWeek(slot.dayOfWeek())
                    .startTime(slot.startTime())
                    .endTime(slot.endTime())
                    .effectiveFrom(request.effectiveFrom())
                    .build());
            saved.add(schedule);
            materialiseInstances(schedule);
        }
        return saved.stream().map(this::toResponse).collect(Collectors.toList());
    }

    @Transactional(readOnly = true)
    public List<ScheduleResponse> currentScheduleForBatch(UUID batchId) {
        return scheduleRepository.findByBatchIdAndEffectiveToIsNull(batchId).stream()
                .map(this::toResponse).collect(Collectors.toList());
    }

    /** The Attendance module's "add a class" - a one-off session that was never on the weekly
     * schedule (scheduleId stays null, same as a Reschedule's replacement instance), immediately
     * available to mark attendance against. Rejects an exact batch+date+startTime duplicate so a
     * double-tap doesn't silently create two class instances for the same session. */
    @Transactional
    @Auditable(action = "CLASS_INSTANCE_ADDED", entityType = "class_instance")
    public ClassInstanceResponse addAdHocInstance(UUID batchId, AddClassInstanceRequest request) {
        if (classInstanceRepository.existsByBatchIdAndDateAndStartTime(batchId, request.date(), request.startTime())) {
            throw new ConflictException("A class already exists for this batch at that date and time.");
        }
        ClassInstance instance = classInstanceRepository.save(ClassInstance.builder()
                .batchId(batchId)
                .date(request.date())
                .startTime(request.startTime())
                .endTime(request.endTime())
                .status(ClassInstanceStatus.SCHEDULED)
                .build());
        return toResponse(instance);
    }

    @Transactional(readOnly = true)
    public List<ClassInstanceResponse> upcomingForBatch(UUID batchId) {
        LocalDate today = LocalDate.now();
        return classInstanceRepository.findByBatchIdAndDateBetween(batchId, today, today.plusWeeks(MATERIALISE_WEEKS_AHEAD))
                .stream().map(this::toResponse).collect(Collectors.toList());
    }

    private void supersedeExistingSchedule(UUID batchId, LocalDate newEffectiveFrom) {
        List<Schedule> stillOpen = scheduleRepository.findByBatchIdAndEffectiveToIsNull(batchId);
        if (stillOpen.isEmpty()) {
            return;
        }

        Set<UUID> supersededScheduleIds = stillOpen.stream().map(Schedule::getId).collect(Collectors.toSet());
        for (Schedule old : stillOpen) {
            old.setEffectiveTo(newEffectiveFrom.minusDays(1));
            scheduleRepository.save(old);
        }

        // Only auto-generated, not-yet-held instances are superseded - a class that already
        // happened (HELD) or was individually moved via Reschedule (no scheduleId) is left alone.
        classInstanceRepository.findByBatchIdAndDateGreaterThanEqual(batchId, newEffectiveFrom).stream()
                .filter(ci -> ci.getScheduleId() != null && supersededScheduleIds.contains(ci.getScheduleId()))
                .filter(ci -> ci.getStatus() == ClassInstanceStatus.SCHEDULED)
                .forEach(ci -> {
                    ci.setStatus(ClassInstanceStatus.CANCELLED);
                    classInstanceRepository.save(ci);
                });
    }

    private void materialiseInstances(Schedule schedule) {
        LocalDate cursor = schedule.getEffectiveFrom();
        LocalDate horizon = cursor.plusWeeks(MATERIALISE_WEEKS_AHEAD);
        while (!cursor.getDayOfWeek().equals(schedule.getDayOfWeek())) {
            cursor = cursor.plusDays(1);
        }
        while (!cursor.isAfter(horizon)) {
            classInstanceRepository.save(ClassInstance.builder()
                    .batchId(schedule.getBatchId())
                    .scheduleId(schedule.getId())
                    .date(cursor)
                    .startTime(schedule.getStartTime())
                    .endTime(schedule.getEndTime())
                    .status(ClassInstanceStatus.SCHEDULED)
                    .build());
            cursor = cursor.plusWeeks(1);
        }
    }

    private ScheduleResponse toResponse(Schedule s) {
        return new ScheduleResponse(s.getId(), s.getBatchId(), s.getDayOfWeek(), s.getStartTime(), s.getEndTime(),
                s.getEffectiveFrom(), s.getEffectiveTo());
    }

    private ClassInstanceResponse toResponse(ClassInstance c) {
        return new ClassInstanceResponse(c.getId(), c.getBatchId(), c.getDate(), c.getStartTime(), c.getEndTime(),
                c.getStatus(), c.getRescheduleReason(), c.getOriginalInstanceId());
    }
}
