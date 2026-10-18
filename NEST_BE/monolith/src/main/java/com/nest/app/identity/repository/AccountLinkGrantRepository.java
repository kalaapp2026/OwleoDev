package com.nest.app.identity.repository;

import com.nest.app.identity.entity.AccountLinkGrant;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.UUID;

public interface AccountLinkGrantRepository extends JpaRepository<AccountLinkGrant, UUID> {
}
