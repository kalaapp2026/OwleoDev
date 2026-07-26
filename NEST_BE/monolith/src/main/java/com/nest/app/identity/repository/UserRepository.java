package com.nest.app.identity.repository;

import com.nest.app.identity.entity.User;
import com.nest.common.security.Role;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;

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
}
