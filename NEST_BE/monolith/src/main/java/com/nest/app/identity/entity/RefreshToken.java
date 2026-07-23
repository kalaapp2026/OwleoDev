package com.nest.app.identity.entity;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Index;
import jakarta.persistence.Table;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

import java.time.Instant;
import java.util.UUID;

/**
 * Server-side session record, one row per issued refresh token. This is what makes "logged in
 * until logout" real instead of aspirational: a JWT by itself can't be un-issued, so logout
 * (and refresh-token rotation) both work by flipping {@code revoked} here, which
 * {@link com.nest.app.identity.service.AuthService#refresh} checks on every use. The access
 * token stays a plain stateless JWT (15 min, not worth tracking) - only the long-lived refresh
 * token needs a revocation point.
 */
@Entity
@Table(name = "refresh_tokens", indexes = @Index(name = "idx_refresh_tokens_user", columnList = "user_id"))
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class RefreshToken {

    /** Same value as the JWT's "jti" claim - correlates a presented token to this row without
     * needing to store the token itself. */
    @Id
    private UUID id;

    @Column(name = "user_id", nullable = false)
    private UUID userId;

    @Column(name = "issued_at", nullable = false)
    private Instant issuedAt;

    @Column(name = "expires_at", nullable = false)
    private Instant expiresAt;

    @Column(nullable = false)
    @Builder.Default
    private boolean revoked = false;

    @Column(name = "revoked_at")
    private Instant revokedAt;
}
