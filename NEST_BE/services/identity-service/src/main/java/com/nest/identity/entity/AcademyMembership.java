package com.nest.identity.entity;

import com.nest.common.security.Role;
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

/**
 * Resolves the many-to-many at the heart of the whole product (PRD 4.4 / Section 7): a user can
 * be Student at Academy A and independently Student/Trainer/Admin at Academy B. Every ERP-scoped
 * row elsewhere (fees, attendance, batch membership, course map) keys off this row's id, NOT
 * user_id - that's what lets a second membership be added later without touching the first one.
 */
@Entity
@Table(name = "academy_memberships", indexes = {
        @Index(name = "idx_membership_user", columnList = "user_id"),
        @Index(name = "idx_membership_academy", columnList = "academy_id")
})
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class AcademyMembership {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(name = "user_id", nullable = false)
    private UUID userId;

    @Column(name = "academy_id", nullable = false)
    private UUID academyId;

    /** Denormalised for JWT claim display purposes only (Academy Switcher labels) - not authoritative. */
    @Column(name = "academy_name")
    private String academyName;

    @Enumerated(EnumType.STRING)
    @Column(name = "role_type", nullable = false)
    private Role roleType;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    @Builder.Default
    private MembershipStatus status = MembershipStatus.ACTIVE;

    @Column(name = "created_by")
    private UUID createdBy;

    @CreationTimestamp
    @Column(name = "created_at", updatable = false)
    private Instant createdAt;
}
