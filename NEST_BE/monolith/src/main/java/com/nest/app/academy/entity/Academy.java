package com.nest.app.academy.entity;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;
import org.hibernate.annotations.CreationTimestamp;
import org.hibernate.annotations.UpdateTimestamp;

import java.time.Instant;
import java.util.UUID;

/**
 * Tenant table (PRD 4.4). Also carries the academy's public About-Us profile (PRD 3.10) - a
 * singleton per academy, editable only by ACADEMY_ADMIN (feature ABOUT_US_EDIT, non-delegable),
 * readable by everyone in the academy. Course highlights, featured trainers, and branches are
 * one-to-many children (see {@link com.nest.app.academy.entity.AcademyHighlight} etc.) since
 * those are genuinely repeatable; every other About-Us field lives directly on this row.
 */
@Entity
@Table(name = "academies", uniqueConstraints = @UniqueConstraint(columnNames = {"name", "city"}))
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class Academy {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(nullable = false)
    private String name;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private AcademyCategory category;

    private String logoUrl;

    @Column(nullable = false)
    private String address;

    @Column(nullable = false)
    private String city;

    @Column(nullable = false)
    private String state;

    @Column(name = "contact_number", nullable = false)
    private String contactNumber;

    private String email;

    /** Short subtitle shown under the institute name on the About page. */
    private String tagline;

    @Column(columnDefinition = "text")
    private String description;

    @Column(name = "established_by")
    private String establishedBy;

    @Column(name = "owner_name")
    private String ownerName;

    @Column(name = "additional_info", columnDefinition = "text")
    private String additionalInfo;

    @Column(name = "instagram_url")
    private String instagramUrl;

    @Column(name = "x_url")
    private String xUrl;

    @Column(name = "facebook_url")
    private String facebookUrl;

    @Column(name = "youtube_url")
    private String youtubeUrl;

    @Column(nullable = false)
    @Builder.Default
    private String plan = "STANDARD";

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    @Builder.Default
    private AcademyStatus status = AcademyStatus.ACTIVE;

    @CreationTimestamp
    @Column(name = "created_at", updatable = false)
    private Instant createdAt;

    @UpdateTimestamp
    @Column(name = "updated_at")
    private Instant updatedAt;
}
