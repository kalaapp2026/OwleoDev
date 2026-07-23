package com.nest.identity.repository;

import com.nest.identity.entity.OtpPurpose;
import com.nest.identity.entity.OtpVerification;
import org.springframework.data.jpa.repository.JpaRepository;

import java.time.Instant;
import java.util.Optional;
import java.util.UUID;

public interface OtpVerificationRepository extends JpaRepository<OtpVerification, UUID> {
    Optional<OtpVerification> findTopByPhoneHashAndPurposeAndConsumedFalseOrderByCreatedAtDesc(
            String phoneHash, OtpPurpose purpose);

    long countByPhoneHashAndPurposeAndCreatedAtAfter(String phoneHash, OtpPurpose purpose, Instant after);
}
