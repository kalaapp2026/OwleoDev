package com.nest.app.scheduling.entity;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.Id;
import jakarta.persistence.Index;
import jakarta.persistence.Table;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

import java.time.LocalDate;
import java.time.LocalTime;
import java.util.UUID;

/**
 * One row per actual/planned class occurrence (PRD 4.4) - the audit-friendly core of Scheduling.
 * {@code scheduleId} is null for Temporary-batch instances and for the NEW instance a Reschedule
 * creates; {@code originalInstanceId} links a rescheduled instance back to the one it replaced.
 */
@Entity
@Table(name = "class_instances", indexes = {
        @Index(name = "idx_class_instances_batch", columnList = "batch_id"),
        @Index(name = "idx_class_instances_date", columnList = "date")
})
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class ClassInstance {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(name = "batch_id", nullable = false)
    private UUID batchId;

    @Column(name = "schedule_id")
    private UUID scheduleId;

    @Column(nullable = false)
    private LocalDate date;

    @Column(name = "start_time", nullable = false)
    private LocalTime startTime;

    @Column(name = "end_time", nullable = false)
    private LocalTime endTime;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    @Builder.Default
    private ClassInstanceStatus status = ClassInstanceStatus.SCHEDULED;

    @Column(name = "reschedule_reason")
    private String rescheduleReason;

    @Column(name = "original_instance_id")
    private UUID originalInstanceId;
}
