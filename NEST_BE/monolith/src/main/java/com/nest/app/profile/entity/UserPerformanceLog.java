package com.nest.app.profile.entity;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

import java.time.LocalDate;
import java.util.UUID;

/** A self-logged result - an exam score, a recital outcome, trainer feedback. */
@Entity
@Table(name = "user_performance_logs")
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class UserPerformanceLog {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(name = "user_id", nullable = false)
    private UUID userId;

    @Column(name = "academy_id")
    private UUID academyId;

    @Column(nullable = false)
    private String title;

    /** EXAM / RECITAL / ASSESSMENT / FEEDBACK. */
    @Column(nullable = false, length = 20)
    private String category;

    @Column(nullable = false)
    private String result;

    private String notes;

    @Column(name = "logged_on", nullable = false)
    private LocalDate loggedOn;
}
