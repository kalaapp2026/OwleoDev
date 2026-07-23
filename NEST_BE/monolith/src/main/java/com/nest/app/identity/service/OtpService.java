package com.nest.app.identity.service;

import com.nest.common.crypto.PiiHasher;
import com.nest.common.exception.BadRequestException;
import com.nest.common.exception.TooManyRequestsException;
import com.nest.app.identity.entity.OtpPurpose;
import com.nest.app.identity.entity.OtpVerification;
import com.nest.app.identity.repository.OtpVerificationRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Duration;
import java.time.Instant;
import java.util.Optional;
import java.util.UUID;

/**
 * OTP lifecycle for both phone login (Phase 1) and the multi-academy membership-confirmation
 * flow (Phase 5, PRD 7.4) - same mechanism, different {@link OtpPurpose} and optional context id.
 */
@Service
public class OtpService {

    private static final Duration CODE_TTL = Duration.ofMinutes(5);
    private static final Duration RATE_LIMIT_WINDOW = Duration.ofMinutes(15);
    private static final long MAX_REQUESTS_PER_WINDOW = 5;
    private static final int MAX_VERIFY_ATTEMPTS = 5;

    // DEV-ONLY: every OTP this service issues is this fixed code, so manual/frontend testing
    // never has to go dig a real code out of LoggingOtpSender's log line. Swap generateCode()
    // back to random once a real WhatsApp/SMS sender replaces LoggingOtpSender (PRD Section 5).
    private static final String DEV_FIXED_CODE = "123456";

    private final OtpVerificationRepository otpRepository;
    private final PiiHasher hasher;
    private final OtpSender sender;

    public OtpService(OtpVerificationRepository otpRepository, PiiHasher hasher, OtpSender sender) {
        this.otpRepository = otpRepository;
        this.hasher = hasher;
        this.sender = sender;
    }

    /** @return the raw code, so callers that also need to show it somewhere other than the SMS/
     * WhatsApp channel (e.g. an in-app notification) don't have to re-derive or store it themselves. */
    @Transactional
    public String requestOtp(String rawPhone, OtpPurpose purpose, UUID contextId) {
        String phoneHash = hasher.hash(rawPhone);

        long recentRequests = otpRepository.countByPhoneHashAndPurposeAndCreatedAtAfter(
                phoneHash, purpose, Instant.now().minus(RATE_LIMIT_WINDOW));
        if (recentRequests >= MAX_REQUESTS_PER_WINDOW) {
            throw new TooManyRequestsException("Too many OTP requests for this phone number - try again later");
        }

        String code = generateCode();
        OtpVerification otp = OtpVerification.builder()
                .phoneHash(phoneHash)
                .codeHash(hasher.hash(code))
                .purpose(purpose)
                .contextId(contextId)
                .expiresAt(Instant.now().plus(CODE_TTL))
                .build();
        otpRepository.save(otp);

        sender.send(rawPhone, code);
        return code;
    }

    /**
     * @return the context id carried by the OTP (e.g. a pending membership id for
     * MEMBERSHIP_CONFIRMATION), or {@code null} for purposes that don't use one.
     */
    @Transactional
    public UUID verifyOtp(String rawPhone, String code, OtpPurpose purpose) {
        String phoneHash = hasher.hash(rawPhone);
        Optional<OtpVerification> maybeOtp =
                otpRepository.findTopByPhoneHashAndPurposeAndConsumedFalseOrderByCreatedAtDesc(phoneHash, purpose);

        OtpVerification otp = maybeOtp.orElseThrow(() -> new BadRequestException("No pending OTP for this phone number"));

        if (otp.isConsumed() || otp.getExpiresAt().isBefore(Instant.now())) {
            throw new BadRequestException("OTP has expired - request a new one");
        }
        if (otp.getAttempts() >= MAX_VERIFY_ATTEMPTS) {
            throw new BadRequestException("Too many incorrect attempts - request a new OTP");
        }

        if (!otp.getCodeHash().equals(hasher.hash(code))) {
            otp.setAttempts(otp.getAttempts() + 1);
            otpRepository.save(otp);
            throw new BadRequestException("Incorrect OTP code");
        }

        otp.setConsumed(true);
        otpRepository.save(otp);
        return otp.getContextId();
    }

    private String generateCode() {
        return DEV_FIXED_CODE;
    }
}
