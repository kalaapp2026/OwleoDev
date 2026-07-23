package com.nest.app.attendance.entity;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.Id;
import jakarta.persistence.Index;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

import java.time.Instant;
import java.util.UUID;

/** PRD 3.8 - one record per (student, class-instance), including rescheduled/temporary instances,
 * so history remains a true log of classes actually held. */
@Entity
@Table(name = "attendance",
        uniqueConstraints = @UniqueConstraint(columnNames = {"class_instance_id", "membership_id"}),
        indexes = {
                @Index(name = "idx_attendance_class_instance", columnList = "class_instance_id"),
                @Index(name = "idx_attendance_membership", columnList = "membership_id")
        })
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class Attendance {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(name = "class_instance_id", nullable = false)
    private UUID classInstanceId;

    @Column(name = "membership_id", nullable = false)
    private UUID membershipId;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private AttendanceStatus status;

    @Column(name = "marked_by", nullable = false)
    private UUID markedBy;

    @Column(name = "marked_at", nullable = false)
    private Instant markedAt;

    private String note;
}
