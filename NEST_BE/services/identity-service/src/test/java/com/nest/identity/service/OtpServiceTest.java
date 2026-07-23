package com.nest.identity.service;

import com.nest.common.crypto.PiiHasher;
import com.nest.common.exception.BadRequestException;
import com.nest.common.exception.TooManyRequestsException;
import com.nest.identity.entity.OtpPurpose;
import com.nest.identity.entity.OtpVerification;
import com.nest.identity.repository.OtpVerificationRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class OtpServiceTest {

    @Mock
    private OtpVerificationRepository otpRepository;
    @Mock
    private PiiHasher hasher;
    @Mock
    private OtpSender sender;

    private OtpService otpService;

    @BeforeEach
    void setUp() {
        otpService = new OtpService(otpRepository, hasher, sender);
        when(hasher.hash(anyString())).thenAnswer(inv -> "hash(" + inv.getArgument(0) + ")");
    }

    @Test
    void fifthRequestWithinWindowIsThrottled() {
        when(otpRepository.countByPhoneHashAndPurposeAndCreatedAtAfter(anyString(), eq(OtpPurpose.LOGIN), any()))
                .thenReturn(5L);

        assertThatThrownBy(() -> otpService.requestOtp("9876543210", OtpPurpose.LOGIN, null))
                .isInstanceOf(TooManyRequestsException.class);
    }

    @Test
    void expiredOtpIsRejectedOnVerify() {
        OtpVerification expired = OtpVerification.builder()
                .phoneHash("hash(9876543210)")
                .codeHash("hash(123456)")
                .purpose(OtpPurpose.LOGIN)
                .consumed(false)
                .expiresAt(Instant.now().minus(1, ChronoUnit.MINUTES))
                .build();
        when(otpRepository.findTopByPhoneHashAndPurposeAndConsumedFalseOrderByCreatedAtDesc("hash(9876543210)", OtpPurpose.LOGIN))
                .thenReturn(Optional.of(expired));

        assertThatThrownBy(() -> otpService.verifyOtp("9876543210", "123456", OtpPurpose.LOGIN))
                .isInstanceOf(BadRequestException.class)
                .hasMessageContaining("expired");
    }

    @Test
    void wrongCodeIsRejectedAndIncrementsAttempts() {
        OtpVerification pending = OtpVerification.builder()
                .phoneHash("hash(9876543210)")
                .codeHash("hash(654321)")
                .purpose(OtpPurpose.LOGIN)
                .consumed(false)
                .attempts(0)
                .expiresAt(Instant.now().plus(5, ChronoUnit.MINUTES))
                .build();
        when(otpRepository.findTopByPhoneHashAndPurposeAndConsumedFalseOrderByCreatedAtDesc("hash(9876543210)", OtpPurpose.LOGIN))
                .thenReturn(Optional.of(pending));

        assertThatThrownBy(() -> otpService.verifyOtp("9876543210", "111111", OtpPurpose.LOGIN))
                .isInstanceOf(BadRequestException.class)
                .hasMessageContaining("Incorrect");

        org.assertj.core.api.Assertions.assertThat(pending.getAttempts()).isEqualTo(1);
    }

    @Test
    void correctCodeConsumesOtpAndReturnsContext() {
        java.util.UUID contextId = java.util.UUID.randomUUID();
        OtpVerification pending = OtpVerification.builder()
                .phoneHash("hash(9876543210)")
                .codeHash("hash(654321)")
                .purpose(OtpPurpose.LOGIN)
                .consumed(false)
                .attempts(0)
                .contextId(contextId)
                .expiresAt(Instant.now().plus(5, ChronoUnit.MINUTES))
                .build();
        when(otpRepository.findTopByPhoneHashAndPurposeAndConsumedFalseOrderByCreatedAtDesc("hash(9876543210)", OtpPurpose.LOGIN))
                .thenReturn(Optional.of(pending));

        java.util.UUID result = otpService.verifyOtp("9876543210", "654321", OtpPurpose.LOGIN);

        org.assertj.core.api.Assertions.assertThat(result).isEqualTo(contextId);
        org.assertj.core.api.Assertions.assertThat(pending.isConsumed()).isTrue();
    }
}
