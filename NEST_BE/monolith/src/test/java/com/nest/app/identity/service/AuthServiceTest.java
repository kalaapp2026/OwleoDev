package com.nest.app.identity.service;

import com.nest.app.identity.dto.AuthMethod;
import com.nest.app.identity.entity.OtpPurpose;
import com.nest.app.identity.entity.RefreshToken;
import com.nest.app.identity.entity.User;
import com.nest.app.identity.repository.RefreshTokenRepository;
import com.nest.app.identity.repository.UserRepository;
import com.nest.common.crypto.PiiHasher;
import com.nest.common.exception.ResourceNotFoundException;
import com.nest.common.exception.UnauthorizedException;
import com.nest.common.security.JwtProperties;
import com.nest.common.security.JwtTokenProvider;
import com.nest.common.security.NestPrincipal;
import com.nest.common.security.Role;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.security.crypto.password.PasswordEncoder;

import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * Covers the session model: refresh tokens are tracked server-side and single-use (rotation), so
 * "logged in until logout" is an enforceable guarantee, not just "until the JWT happens to expire."
 * Uses a real {@link JwtTokenProvider} (cheap, no DB/network) rather than mocking it, since the
 * whole point under test is the real jti round-trip between token and tracked row.
 */
@ExtendWith(MockitoExtension.class)
class AuthServiceTest {

    @Mock
    private UserRepository userRepository;
    @Mock
    private RefreshTokenRepository refreshTokenRepository;
    @Mock
    private PiiHasher hasher;
    @Mock
    private PasswordEncoder passwordEncoder;
    @Mock
    private PrincipalAssembler principalAssembler;
    @Mock
    private OtpService otpService;

    private JwtTokenProvider tokenProvider;
    private AuthService authService;

    private final UUID userId = UUID.randomUUID();

    @BeforeEach
    void setUp() {
        tokenProvider = new JwtTokenProvider(new JwtProperties());
        authService = new AuthService(userRepository, refreshTokenRepository, hasher, passwordEncoder,
                tokenProvider, principalAssembler, otpService);
    }

    private User adminUser() {
        return User.builder().id(userId).username("meera").passwordHash("hashed").role(Role.ACADEMY_ADMIN).fullName("Meera").build();
    }

    private User studentUser() {
        return User.builder().id(UUID.randomUUID()).username("priya_r").passwordHash(null)
                .phone("9876543210").role(Role.STUDENT).fullName("Priya").build();
    }

    private void stubAssembly() {
        when(principalAssembler.assemble(any(User.class)))
                .thenReturn(new NestPrincipal(userId, "meera", Role.ACADEMY_ADMIN, List.of(), null));
        when(principalAssembler.summarise(any(User.class))).thenReturn(List.of());
    }

    @Test
    void loginPersistsATrackedRefreshTokenRow() {
        when(userRepository.findByUsername("meera")).thenReturn(Optional.of(adminUser()));
        when(passwordEncoder.matches("correct", "hashed")).thenReturn(true);
        stubAssembly();

        authService.loginWithPassword("meera", "correct");

        verify(refreshTokenRepository).save(any(RefreshToken.class));
    }

    @Test
    void refreshWithValidTokenRotatesItAndIssuesANewOne() {
        UUID jti = UUID.randomUUID();
        String refreshTokenString = tokenProvider.generateRefreshToken(userId, jti);
        RefreshToken tracked = RefreshToken.builder().id(jti).userId(userId)
                .issuedAt(Instant.now()).expiresAt(Instant.now().plus(30, ChronoUnit.DAYS)).revoked(false).build();

        when(refreshTokenRepository.findById(jti)).thenReturn(Optional.of(tracked));
        when(userRepository.findById(userId)).thenReturn(Optional.of(adminUser()));
        stubAssembly();

        var response = authService.refresh(refreshTokenString);

        assertThat(tracked.isRevoked()).as("the presented token must be revoked on use (rotation)").isTrue();
        assertThat(response.refreshToken()).isNotEqualTo(refreshTokenString);
        verify(refreshTokenRepository, times(2)).save(any(RefreshToken.class)); // revoke old + persist new
    }

    @Test
    void refreshWithRevokedTokenIsRejected() {
        UUID jti = UUID.randomUUID();
        String refreshTokenString = tokenProvider.generateRefreshToken(userId, jti);
        RefreshToken tracked = RefreshToken.builder().id(jti).userId(userId)
                .issuedAt(Instant.now()).expiresAt(Instant.now().plus(30, ChronoUnit.DAYS)).revoked(true).build();

        when(refreshTokenRepository.findById(jti)).thenReturn(Optional.of(tracked));

        assertThatThrownBy(() -> authService.refresh(refreshTokenString))
                .isInstanceOf(UnauthorizedException.class)
                .hasMessageContaining("logged out");
    }

    @Test
    void refreshWithUnknownJtiIsRejected() {
        UUID jti = UUID.randomUUID();
        String refreshTokenString = tokenProvider.generateRefreshToken(userId, jti);
        when(refreshTokenRepository.findById(jti)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> authService.refresh(refreshTokenString))
                .isInstanceOf(UnauthorizedException.class)
                .hasMessageContaining("Unknown session");
    }

    @Test
    void logoutRevokesTheTrackedToken() {
        UUID jti = UUID.randomUUID();
        String refreshTokenString = tokenProvider.generateRefreshToken(userId, jti);
        RefreshToken tracked = RefreshToken.builder().id(jti).userId(userId)
                .issuedAt(Instant.now()).expiresAt(Instant.now().plus(30, ChronoUnit.DAYS)).revoked(false).build();
        when(refreshTokenRepository.findById(jti)).thenReturn(Optional.of(tracked));

        authService.logout(refreshTokenString);

        assertThat(tracked.isRevoked()).isTrue();
        assertThat(tracked.getRevokedAt()).isNotNull();
    }

    @Test
    void logoutWithAlreadyRevokedOrUnknownTokenIsIdempotentNotAnError() {
        UUID jti = UUID.randomUUID();
        String refreshTokenString = tokenProvider.generateRefreshToken(userId, jti);
        when(refreshTokenRepository.findById(jti)).thenReturn(Optional.empty());

        authService.logout(refreshTokenString); // must not throw

        verify(refreshTokenRepository, never()).save(any());
    }

    @Test
    void loggedOutSessionCannotBeUsedToRefreshAgain() {
        UUID jti = UUID.randomUUID();
        String refreshTokenString = tokenProvider.generateRefreshToken(userId, jti);
        RefreshToken tracked = RefreshToken.builder().id(jti).userId(userId)
                .issuedAt(Instant.now()).expiresAt(Instant.now().plus(30, ChronoUnit.DAYS)).revoked(false).build();
        when(refreshTokenRepository.findById(jti)).thenReturn(Optional.of(tracked));

        authService.logout(refreshTokenString);
        assertThat(tracked.isRevoked()).isTrue();

        // Same repository state (revoked=true) is what a second lookup would see post-logout.
        assertThatThrownBy(() -> authService.refresh(refreshTokenString))
                .isInstanceOf(UnauthorizedException.class);
    }

    @Test
    void changePasswordRevokesAllOtherSessions() {
        User user = adminUser();
        when(userRepository.findById(userId)).thenReturn(Optional.of(user));
        when(passwordEncoder.matches(eq("old"), eq("hashed"))).thenReturn(true);
        when(passwordEncoder.encode("newpassword")).thenReturn("newhash");

        authService.changePassword(userId, new com.nest.app.identity.dto.ChangePasswordRequest("old", "newpassword"));

        verify(refreshTokenRepository).revokeAllForUser(userId);
    }

    @Test
    void identifyByUsernameOfPasswordAccountAsksForPassword() {
        when(userRepository.findByUsername("meera")).thenReturn(Optional.of(adminUser()));

        var result = authService.identify("meera");

        assertThat(result.authMethod()).isEqualTo(AuthMethod.PASSWORD);
        assertThat(result.username()).isEqualTo("meera");
        assertThat(result.maskedPhone()).isNull();
        verify(otpService, never()).requestOtp(any(), any(), any());
    }

    @Test
    void identifyByUsernameOfOtpOnlyAccountSendsOtpAndAsksForCode() {
        User student = studentUser();
        when(userRepository.findByUsername("priya_r")).thenReturn(Optional.of(student));

        var result = authService.identify("priya_r");

        assertThat(result.authMethod()).isEqualTo(AuthMethod.OTP);
        assertThat(result.username()).isEqualTo("priya_r");
        assertThat(result.maskedPhone()).isEqualTo("xxxxxxxx10");
        verify(otpService).requestOtp(eq("9876543210"), eq(OtpPurpose.LOGIN), eq(null));
    }

    @Test
    void identifyByPhoneFallsBackToPhoneLookupWhenNotAUsername() {
        User student = studentUser();
        when(userRepository.findByUsername("9876543210")).thenReturn(Optional.empty());
        when(hasher.hash("9876543210")).thenReturn("hashed-phone");
        when(userRepository.findAllByPhoneHash("hashed-phone")).thenReturn(List.of(student));

        var result = authService.identify("9876543210");

        assertThat(result.authMethod()).isEqualTo(AuthMethod.OTP);
    }

    @Test
    void identifyWithUnknownIdentifierIsRejected() {
        when(userRepository.findByUsername("ghost")).thenReturn(Optional.empty());
        when(hasher.hash("ghost")).thenReturn("hashed-ghost");
        when(userRepository.findAllByPhoneHash("hashed-ghost")).thenReturn(List.of());

        assertThatThrownBy(() -> authService.identify("ghost"))
                .isInstanceOf(ResourceNotFoundException.class);
    }

    @Test
    void identifyByPhoneSharedAcrossTwoAccountsAsksForUsernameInstead() {
        User child1 = studentUser();
        User child2 = User.builder().id(UUID.randomUUID()).username("priya_k").phone("9876543210").role(Role.STUDENT).fullName("Priya K").build();
        when(userRepository.findByUsername("9876543210")).thenReturn(Optional.empty());
        when(hasher.hash("9876543210")).thenReturn("hashed-phone");
        when(userRepository.findAllByPhoneHash("hashed-phone")).thenReturn(List.of(child1, child2));

        assertThatThrownBy(() -> authService.identify("9876543210"))
                .isInstanceOf(com.nest.common.exception.BadRequestException.class)
                .hasMessageContaining("username");
    }
}
