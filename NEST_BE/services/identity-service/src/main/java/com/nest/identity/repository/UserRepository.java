package com.nest.identity.repository;

import com.nest.identity.entity.User;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Optional;
import java.util.UUID;

public interface UserRepository extends JpaRepository<User, UUID> {
    Optional<User> findByUsername(String username);

    Optional<User> findByPhoneHash(String phoneHash);

    boolean existsByUsername(String username);

    boolean existsByPhoneHash(String phoneHash);
}
