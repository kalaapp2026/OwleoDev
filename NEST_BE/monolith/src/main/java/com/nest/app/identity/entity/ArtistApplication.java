package com.nest.app.identity.entity;

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
import org.hibernate.annotations.CreationTimestamp;

import java.time.Instant;
import java.util.UUID;

/** A Guest's request to become an Artist (PRD 7.4 addendum) - Super Admin approves or rejects.
 * Approval flips {@link User#getRole()} to ARTIST directly; this row is only the request/decision
 * record, not itself the source of truth for who currently is an artist. */
@Entity
@Table(name = "artist_applications", indexes = {
        @Index(name = "idx_artist_applications_user", columnList = "user_id"),
        @Index(name = "idx_artist_applications_status", columnList = "status")
})
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class ArtistApplication {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(name = "user_id", nullable = false)
    private UUID userId;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    @Builder.Default
    private ArtistApplicationStatus status = ArtistApplicationStatus.PENDING;

    @Column(name = "decided_by")
    private UUID decidedBy;

    @Column(name = "decided_at")
    private Instant decidedAt;

    /** What the applicant told us, kept for HQ's review (V57). */
    @Column(name = "art_form", length = 80)
    private String artForm;

    @Column(length = 80)
    private String city;

    @Column(length = 500)
    private String bio;

    /** JSON list of {pl, h, f, s, m, note}: the profiles they linked and HQ's check of each. */
    @Column(nullable = false)
    @Builder.Default
    private String profiles = "[]";

    @CreationTimestamp
    @Column(name = "created_at", updatable = false)
    private Instant createdAt;
}
