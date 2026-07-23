package com.nest.identity.service;

import com.nest.common.crypto.PiiHasher;
import com.nest.common.exception.BadRequestException;
import com.nest.common.exception.UnauthorizedException;
import com.nest.common.security.JwtTokenProvider;
import com.nest.common.security.NestPrincipal;
import com.nest.common.security.Role;
import com.nest.identity.entity.User;
import com.nest.identity.repository.UserRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.security.crypto.password.PasswordEncoder;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class AuthServiceTest {

    @Mock
    private UserRepository userRepository;
    @Mock
    private PiiHasher hasher;
    @Mock
    private PasswordEncoder passwordEncoder;
    @Mock
    private JwtTokenProvider tokenProvider;
    @Mock
    private PrincipalAssembler principalAssembler;
    @Mock
    private OtpService otpService;

    private AuthService authService;

    @BeforeEach
    void setUp() {
        authService = new AuthService(userRepository, hasher, passwordEncoder, tokenProvider, principalAssembler, otpService);
    }

    @Test
    void unknownUsernameIsRejectedAsInvalidCredentials() {
        when(userRepository.findByUsername("ghost")).thenReturn(Optional.empty());

        assertThatThrownBy(() -> authService.loginWithPassword("ghost", "whatever"))
                .isInstanceOf(UnauthorizedException.class);
    }

    @Test
    void otpOnlyAccountCannotLoginWithPassword() {
        User student = User.builder().id(UUID.randomUUID()).username("priya_r").passwordHash(null).build();
        when(userRepository.findByUsername("priya_r")).thenReturn(Optional.of(student));

        assertThatThrownBy(() -> authService.loginWithPassword("priya_r", "anything"))
                .isInstanceOf(BadRequestException.class)
                .hasMessageContaining("OTP login");
    }

    @Test
    void wrongPasswordIsRejected() {
        User admin = User.builder().id(UUID.randomUUID()).username("meera").passwordHash("hashed").build();
        when(userRepository.findByUsername("meera")).thenReturn(Optional.of(admin));
        when(passwordEncoder.matches("wrong", "hashed")).thenReturn(false);

        assertThatThrownBy(() -> authService.loginWithPassword("meera", "wrong"))
                .isInstanceOf(UnauthorizedException.class);
    }

    @Test
    void correctPasswordIssuesTokens() {
        UUID userId = UUID.randomUUID();
        User admin = User.builder().id(userId).username("meera").passwordHash("hashed")
                .role(Role.ACADEMY_ADMIN).fullName("Meera").build();
        when(userRepository.findByUsername("meera")).thenReturn(Optional.of(admin));
        when(passwordEncoder.matches("correct", "hashed")).thenReturn(true);
        when(principalAssembler.assemble(admin)).thenReturn(new NestPrincipal(userId, "meera", Role.ACADEMY_ADMIN, List.of(), null));
        when(principalAssembler.summarise(admin)).thenReturn(List.of());
        when(tokenProvider.generateAccessToken(any())).thenReturn("access-token");
        when(tokenProvider.generateRefreshToken(eq(userId))).thenReturn("refresh-token");

        var response = authService.loginWithPassword("meera", "correct");

        org.assertj.core.api.Assertions.assertThat(response.accessToken()).isEqualTo("access-token");
        org.assertj.core.api.Assertions.assertThat(response.refreshToken()).isEqualTo("refresh-token");
    }
}
