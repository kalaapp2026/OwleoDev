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

/** Something the person earned - an award, a certificate, a streak. Self-recorded. */
@Entity
@Table(name = "user_achievements")
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class UserAchievement {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(name = "user_id", nullable = false)
    private UUID userId;

    @Column(name = "academy_id")
    private UUID academyId;

    @Column(nullable = false)
    private String title;

    private String description;

    /** AWARD / STREAK / CERTIFICATE / MILESTONE. A string rather than an enum so a new kind
     * needs no migration; the service validates against the known set. */
    @Column(nullable = false, length = 20)
    private String type;

    @Column(name = "achieved_on", nullable = false)
    private LocalDate achievedOn;
}
