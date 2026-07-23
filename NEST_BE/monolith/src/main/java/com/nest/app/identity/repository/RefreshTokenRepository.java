package com.nest.app.identity.repository;

import com.nest.app.identity.entity.RefreshToken;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.UUID;

public interface RefreshTokenRepository extends JpaRepository<RefreshToken, UUID> {

    /** Logout-everywhere / password-change-invalidates-sessions support. */
    @Modifying
    @Query("update RefreshToken t set t.revoked = true, t.revokedAt = CURRENT_TIMESTAMP where t.userId = :userId and t.revoked = false")
    void revokeAllForUser(@Param("userId") UUID userId);
}
