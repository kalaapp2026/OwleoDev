package com.nest.app.identity.repository;

import com.nest.app.identity.entity.User;
import com.nest.common.security.Role;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

public interface UserRepository extends JpaRepository<User, UUID> {
    Optional<User> findByUsername(String username);

    /** Who to notify when a new artist application comes in. */
    List<User> findByRole(Role role);

    /** People search (Social "Search" tab) - partial, case-insensitive match on either field. */
    List<User> findByUsernameContainingIgnoreCaseOrFullNameContainingIgnoreCase(String username, String fullName, Pageable pageable);

    /** Phone is no longer unique - may return more than one account for a shared family phone. */
    List<User> findAllByPhoneHash(String phoneHash);

    Optional<User> findByEmailIgnoreCase(String email);

    /** Legacy OTP-only accounts (Students/Guests/Artists created before unified password login) -
     * the one-time backfill gives each of these a temp password so they can log in like everyone. */
    List<User> findByPasswordHashIsNull();

    boolean existsByUsername(String username);

    boolean existsByEmailIgnoreCase(String email);

    // ---- Super Admin platform metrics ----

    /** Bulk update rather than load-modify-save: this runs on the request hot path, and loading a
     * whole User just to stamp one timestamp would also risk clobbering concurrent edits. */
    @Modifying(clearAutomatically = true)
    @Query("update User u set u.lastSeenAt = :seenAt where u.id = :userId")
    void touchLastSeen(@Param("userId") UUID userId, @Param("seenAt") Instant seenAt);

    long countByRole(Role role);

    /** Active-user counts - pass now-1h for "active now", now-24h for DAU, etc. */
    long countByLastSeenAtAfter(Instant since);

    long countByCreatedAtAfter(Instant since);

    /** Signup trend: one row per (day, count), ordered oldest first, for the dashboard's chart. */
    @Query("""
            select function('date_trunc', 'day', u.createdAt) as day, count(u)
            from User u where u.createdAt >= :since
            group by function('date_trunc', 'day', u.createdAt)
            order by function('date_trunc', 'day', u.createdAt)
            """)
    List<Object[]> countSignupsPerDaySince(@Param("since") Instant since);
}
