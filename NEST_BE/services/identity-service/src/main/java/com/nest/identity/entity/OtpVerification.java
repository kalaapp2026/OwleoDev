package com.nest.identity.entity;

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
 * One-time codes for phone login and (from Phase 5) multi-academy membership confirmation.
 * {@code phoneHash} is looked up the same deterministic way as {@link User#getPhoneHash()} so we
 * never need to decrypt PII just to find the right row. The raw code itself is stored hashed
 * (never in plaintext) so a DB read alone can't be used to impersonate someone.
 */
@Entity
@Table(name = "otp_verifications", indexes = @Index(name = "idx_otp_phone_hash", columnList = "phone_hash"))
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class OtpVerification {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(name = "phone_hash", nullable = false, length = 64)
    private String phoneHash;

    @Column(name = "code_hash", nullable = false)
    private String codeHash;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private OtpPurpose purpose;

    /** For MEMBERSHIP_CONFIRMATION: the pending academy_memberships.id this OTP will activate. */
    @Column(name = "context_id")
    private UUID contextId;

    @Column(nullable = false)
    @Builder.Default
    private int attempts = 0;

    @Column(nullable = false)
    @Builder.Default
    private boolean consumed = false;

    @Column(name = "expires_at", nullable = false)
    private Instant expiresAt;

    @CreationTimestamp
    @Column(name = "created_at", updatable = false)
    private Instant createdAt;
}
