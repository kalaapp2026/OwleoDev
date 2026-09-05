package com.nest.app.identity.entity;

import com.nest.common.security.Role;
import jakarta.persistence.CollectionTable;
import jakarta.persistence.Column;
import jakarta.persistence.ElementCollection;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.Id;
import jakarta.persistence.Index;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.MapKeyColumn;
import jakarta.persistence.Table;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;
import org.hibernate.annotations.CreationTimestamp;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.HashMap;
import java.util.Map;
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

    /**
     * The date this person joined THIS academy.
     *
     * <p>A property of the membership rather than the user: the same person can join a second
     * academy years later, and {@code users.createdAt} answers a different question - when the
     * account first existed anywhere.
     */
    @Column(name = "joining_date")
    private java.time.LocalDate joiningDate;

    /**
     * What this academy pays this trainer, per month. Null means "not recorded", which is
     * different from zero - the registration form leaves it optional.
     *
     * <p>Lives here rather than on the user because the same trainer can teach at two academies
     * for two different amounts, and neither should be able to read the other's figure.
     */
    @Column(name = "salary")
    private java.math.BigDecimal salary;

    @Column(name = "created_by")
    private UUID createdBy;

    @CreationTimestamp
    @Column(name = "created_at", updatable = false)
    private Instant createdAt;

    /** Courses staged on this (already-ACTIVE) membership while the registering Trainer/Admin
     * lacks course-overlap visibility of this person - applied once they confirm via OTP
     * (PRD 7.4 addendum). Empty for the common case. */
    @ElementCollection
    @CollectionTable(name = "membership_pending_course_fees", joinColumns = @JoinColumn(name = "membership_id"))
    @MapKeyColumn(name = "course_id")
    @Column(name = "fee")
    @Builder.Default
    private Map<UUID, BigDecimal> pendingCourseFees = new HashMap<>();
}
