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

/**
 * One-time codes for phone login, (from Phase 5) multi-academy membership confirmation, and
 * (email-delivered) password reset. Exactly one of {@code phoneHash}/{@code emailHash} is set per
 * row, depending on the purpose's delivery channel - both are looked up the same deterministic way
 * as {@link User#getPhoneHash()} so we never need to decrypt PII just to find the right row. The
 * raw code itself is stored hashed (never in plaintext) so a DB read alone can't be used to
 * impersonate someone.
 */
@Entity
@Table(name = "otp_verifications", indexes = {
        @Index(name = "idx_otp_phone_hash", columnList = "phone_hash"),
        @Index(name = "idx_otp_email_hash", columnList = "email_hash"),
})
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class OtpVerification {

    @Id
    @GeneratedValue
    private UUID id;

    /** Null for email-delivered purposes (PASSWORD_RESET). */
    @Column(name = "phone_hash", length = 64)
    private String phoneHash;

    /** Null for phone-delivered purposes (LOGIN, REGISTRATION, MEMBERSHIP_CONFIRMATION). */
    @Column(name = "email_hash", length = 64)
    private String emailHash;

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
