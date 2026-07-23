package com.nest.identity.service;

import com.nest.common.crypto.PiiHasher;
import com.nest.common.exception.BadRequestException;
import com.nest.common.exception.ResourceNotFoundException;
import com.nest.common.exception.UnauthorizedException;
import com.nest.common.security.JwtTokenProvider;
import com.nest.common.security.NestPrincipal;
import com.nest.identity.dto.AuthResponse;
import com.nest.identity.dto.ChangePasswordRequest;
import com.nest.identity.dto.UserProfileResponse;
import com.nest.identity.entity.OtpPurpose;
import com.nest.identity.entity.User;
import com.nest.identity.repository.UserRepository;
import io.jsonwebtoken.Claims;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.UUID;

@Service
public class AuthService {

    private static final long ACCESS_TOKEN_TTL_SECONDS = 15 * 60L;

    private final UserRepository userRepository;
    private final PiiHasher hasher;
    private final PasswordEncoder passwordEncoder;
    private final JwtTokenProvider tokenProvider;
    private final PrincipalAssembler principalAssembler;
    private final OtpService otpService;

    public AuthService(UserRepository userRepository, PiiHasher hasher, PasswordEncoder passwordEncoder,
                        JwtTokenProvider tokenProvider, PrincipalAssembler principalAssembler, OtpService otpService) {
        this.userRepository = userRepository;
        this.hasher = hasher;
        this.passwordEncoder = passwordEncoder;
        this.tokenProvider = tokenProvider;
        this.principalAssembler = principalAssembler;
        this.otpService = otpService;
    }

    @Transactional(readOnly = true)
    public AuthResponse loginWithPassword(String username, String rawPassword) {
        User user = userRepository.findByUsername(username)
                .orElseThrow(() -> new UnauthorizedException("Invalid username or password"));

        if (user.getPasswordHash() == null) {
            throw new BadRequestException("This account uses OTP login, not a password");
        }
        if (!passwordEncoder.matches(rawPassword, user.getPasswordHash())) {
            throw new UnauthorizedException("Invalid username or password");
        }

        return issueTokens(user);
    }

    @Transactional
    public void requestLoginOtp(String rawPhone) {
        String phoneHash = hasher.hash(rawPhone);
        if (!userRepository.existsByPhoneHash(phoneHash)) {
            throw new ResourceNotFoundException("No NEST account found for this phone number");
        }
        otpService.requestOtp(rawPhone, OtpPurpose.LOGIN, null);
    }

    @Transactional(readOnly = true)
    public AuthResponse loginWithOtp(String rawPhone, String code) {
        otpService.verifyOtp(rawPhone, code, OtpPurpose.LOGIN);

        User user = userRepository.findByPhoneHash(hasher.hash(rawPhone))
                .orElseThrow(() -> new ResourceNotFoundException("No NEST account found for this phone number"));

        return issueTokens(user);
    }

    @Transactional(readOnly = true)
    public AuthResponse refresh(String refreshToken) {
        Claims claims = tokenProvider.parse(refreshToken);
        if (!tokenProvider.isRefreshToken(claims)) {
            throw new UnauthorizedException("Expected a refresh token");
        }
        UUID userId = UUID.fromString(claims.getSubject());
        User user = userRepository.findById(userId)
                .orElseThrow(() -> new UnauthorizedException("User no longer exists"));

        // Rebuilt fresh (not trusted from the old token) so a feature-grant/membership change
        // since the original login takes effect immediately on refresh.
        return issueTokens(user);
    }

    @Transactional
    public void changePassword(UUID userId, ChangePasswordRequest request) {
        User user = userRepository.findById(userId)
                .orElseThrow(() -> new ResourceNotFoundException("User not found"));

        if (user.getPasswordHash() == null || !passwordEncoder.matches(request.currentPassword(), user.getPasswordHash())) {
            throw new UnauthorizedException("Current password is incorrect");
        }

        user.setPasswordHash(passwordEncoder.encode(request.newPassword()));
        user.setTemporaryPassword(false);
        userRepository.save(user);
    }

    private AuthResponse issueTokens(User user) {
        NestPrincipal principal = principalAssembler.assemble(user);
        String accessToken = tokenProvider.generateAccessToken(principal);
        String refreshToken = tokenProvider.generateRefreshToken(user.getId());

        UserProfileResponse profile = new UserProfileResponse(
                user.getId(), user.getUsername(), user.getFullName(), maskPhone(user.getPhone()), user.getEmail(),
                user.getCity(), user.getState(), user.getRole(), user.isTemporaryPassword(), user.getThemePreference(),
                principalAssembler.summarise(user), principal.activeMembershipId()
        );

        return AuthResponse.of(accessToken, refreshToken, ACCESS_TOKEN_TTL_SECONDS, profile);
    }

    private String maskPhone(String phone) {
        if (phone == null || phone.length() < 4) {
            return phone;
        }
        int visibleTail = 2;
        String tail = phone.substring(phone.length() - visibleTail);
        return "x".repeat(phone.length() - visibleTail) + tail;
    }
}
