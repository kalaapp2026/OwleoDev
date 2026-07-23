package com.nest.app.identity.service;

import com.nest.app.identity.dto.AuthMethod;
import com.nest.app.identity.dto.AuthResponse;
import com.nest.app.identity.dto.ChangePasswordRequest;
import com.nest.app.identity.dto.IdentifyResponse;
import com.nest.app.identity.dto.UserProfileResponse;
import com.nest.app.identity.entity.OtpPurpose;
import com.nest.app.identity.entity.RefreshToken;
import com.nest.app.identity.entity.User;
import com.nest.app.identity.repository.RefreshTokenRepository;
import com.nest.app.identity.repository.UserRepository;
import com.nest.common.audit.Auditable;
import com.nest.common.crypto.PiiHasher;
import com.nest.common.exception.BadRequestException;
import com.nest.common.exception.ResourceNotFoundException;
import com.nest.common.exception.UnauthorizedException;
import com.nest.common.security.JwtTokenProvider;
import com.nest.common.security.NestPrincipal;
import io.jsonwebtoken.Claims;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

/**
 * Session model: the access token is a short-lived (15 min), purely stateless JWT - not worth
 * tracking, it just expires. The refresh token is long-lived (30 days) AND tracked server-side
 * via {@link RefreshToken}, which is what makes "stay logged in until you log out" a real,
 * enforceable guarantee instead of just "until the token happens to expire." A client (the
 * Flutter app) is expected to silently call {@link #refresh} whenever an API call comes back 401
 * with an expired access token, using the refresh token it already has - the user never sees a
 * login screen again unless they explicitly log out or 30 days pass with the app never opened.
 */
@Service
public class AuthService {

    private static final long ACCESS_TOKEN_TTL_SECONDS = 15 * 60L;

    private final UserRepository userRepository;
    private final RefreshTokenRepository refreshTokenRepository;
    private final PiiHasher hasher;
    private final PasswordEncoder passwordEncoder;
    private final JwtTokenProvider tokenProvider;
    private final PrincipalAssembler principalAssembler;
    private final OtpService otpService;

    public AuthService(UserRepository userRepository, RefreshTokenRepository refreshTokenRepository, PiiHasher hasher,
                        PasswordEncoder passwordEncoder, JwtTokenProvider tokenProvider,
                        PrincipalAssembler principalAssembler, OtpService otpService) {
        this.userRepository = userRepository;
        this.refreshTokenRepository = refreshTokenRepository;
        this.hasher = hasher;
        this.passwordEncoder = passwordEncoder;
        this.tokenProvider = tokenProvider;
        this.principalAssembler = principalAssembler;
        this.otpService = otpService;
    }

    /**
     * Single unified entry point: the caller types one identifier (username OR phone) and the
     * backend decides whether this account needs a password or an OTP - no manual "Admin/Trainer
     * vs Student/Guest" tab for the user to pick themselves. If the account is OTP-based, this
     * also sends the code as a side effect, so the client's very next call is straight to
     * /auth/otp/verify with no separate "request" step.
     */
    @Transactional
    public IdentifyResponse identify(String identifier) {
        User user = resolveByIdentifier(identifier);

        if (user.getPasswordHash() != null) {
            return new IdentifyResponse(AuthMethod.PASSWORD, user.getUsername(), null);
        }

        otpService.requestOtp(user.getPhone(), OtpPurpose.LOGIN, null);
        return new IdentifyResponse(AuthMethod.OTP, user.getUsername(), maskPhone(user.getPhone()));
    }

    /** Username-or-phone resolution, shared by every step of the unified login flow (identify,
     * OTP verify, OTP resend) so the client can always send back whatever the user originally
     * typed - it never needs to remember/re-derive which lookup type that was. Phone is no longer
     * unique (a family may share one number across accounts), so a phone match that resolves to
     * more than one account is ambiguous - the caller must fall back to their username instead. */
    private User resolveByIdentifier(String identifier) {
        Optional<User> byUsername = userRepository.findByUsername(identifier);
        if (byUsername.isPresent()) {
            return byUsername.get();
        }

        List<User> byPhone = userRepository.findAllByPhoneHash(hasher.hash(identifier));
        if (byPhone.isEmpty()) {
            throw new ResourceNotFoundException("No NEST account found for '" + identifier + "'");
        }
        if (byPhone.size() > 1) {
            throw new BadRequestException(
                    "More than one NEST account uses this phone number - please log in with your username instead");
        }
        return byPhone.get(0);
    }

    @Transactional
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

    /** Resend, for the "code sent" screen's "didn't get it?" link - identifier may be a username
     * or a phone, same as every other step. */
    @Transactional
    public void requestLoginOtp(String identifier) {
        User user = resolveByIdentifier(identifier);
        otpService.requestOtp(user.getPhone(), OtpPurpose.LOGIN, null);
    }

    @Transactional
    public AuthResponse loginWithOtp(String identifier, String code) {
        User user = resolveByIdentifier(identifier);
        otpService.verifyOtp(user.getPhone(), code, OtpPurpose.LOGIN);
        return issueTokens(user);
    }

    /**
     * Rotates the refresh token on every use: the presented one is revoked and a brand new one
     * issued, so a refresh token is single-use. If a revoked or unknown token is ever presented
     * again, that's a strong signal of theft/replay, not normal client behaviour - reject outright
     * rather than silently issuing new tokens anyway.
     */
    @Transactional
    public AuthResponse refresh(String refreshToken) {
        RefreshToken tracked = validateAndConsumeRefreshToken(refreshToken);

        User user = userRepository.findById(tracked.getUserId())
                .orElseThrow(() -> new UnauthorizedException("User no longer exists"));

        // Rebuilt fresh (not trusted from the old token) so a feature-grant/membership change
        // since the original login takes effect immediately on refresh.
        return issueTokens(user);
    }

    @Transactional
    @Auditable(action = "USER_LOGGED_OUT", entityType = "refresh_token")
    public void logout(String refreshToken) {
        Claims claims = tokenProvider.parse(refreshToken);
        if (!tokenProvider.isRefreshToken(claims)) {
            throw new UnauthorizedException("Expected a refresh token");
        }
        UUID jti = UUID.fromString(claims.getId());
        refreshTokenRepository.findById(jti).ifPresent(this::revoke);
        // Unknown/already-revoked token: logout is idempotent, not an error - the end state
        // ("this session is not usable") is already true either way.
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

        // A password change should invalidate every other device's session, not just this one.
        refreshTokenRepository.revokeAllForUser(userId);
    }

    private RefreshToken validateAndConsumeRefreshToken(String refreshToken) {
        Claims claims = tokenProvider.parse(refreshToken);
        if (!tokenProvider.isRefreshToken(claims)) {
            throw new UnauthorizedException("Expected a refresh token");
        }

        UUID jti = UUID.fromString(claims.getId());
        RefreshToken tracked = refreshTokenRepository.findById(jti)
                .orElseThrow(() -> new UnauthorizedException("Unknown session - please log in again"));

        if (tracked.isRevoked()) {
            throw new UnauthorizedException("This session has been logged out - please log in again");
        }
        if (tracked.getExpiresAt().isBefore(Instant.now())) {
            throw new UnauthorizedException("Session expired - please log in again");
        }

        revoke(tracked);
        return tracked;
    }

    private void revoke(RefreshToken token) {
        token.setRevoked(true);
        token.setRevokedAt(Instant.now());
        refreshTokenRepository.save(token);
    }

    private AuthResponse issueTokens(User user) {
        NestPrincipal principal = principalAssembler.assemble(user);
        String accessToken = tokenProvider.generateAccessToken(principal);

         UUID jti = UUID.randomUUID();
        String refreshToken = tokenProvider.generateRefreshToken(user.getId(), jti);
        Instant refreshExpiresAt = tokenProvider.parse(refreshToken).getExpiration().toInstant();
        refreshTokenRepository.save(RefreshToken.builder()
                .id(jti)
                .userId(user.getId())
                .issuedAt(Instant.now())
                .expiresAt(refreshExpiresAt)
                .revoked(false)
                .build());

        UserProfileResponse profile = new UserProfileResponse(
                user.getId(), user.getUsername(), user.getFullName(), maskPhone(user.getPhone()), user.getEmail(),
                user.getCity(), user.getState(), user.getRole(), user.isTemporaryPassword(), user.getThemePreference(),
                principalAssembler.summarise(user), principal.activeMembershipId(), user.getProfileImageUrl()
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
