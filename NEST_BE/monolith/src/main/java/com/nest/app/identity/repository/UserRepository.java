package com.nest.app.identity.repository;

import com.nest.app.identity.entity.User;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

public interface UserRepository extends JpaRepository<User, UUID> {
    Optional<User> findByUsername(String username);

    /** Phone is no longer unique - may return more than one account for a shared family phone. */
    List<User> findAllByPhoneHash(String phoneHash);

    Optional<User> findByEmailIgnoreCase(String email);

    boolean existsByUsername(String username);

    boolean existsByEmailIgnoreCase(String email);
}
