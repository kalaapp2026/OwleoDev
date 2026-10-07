package com.nest.app.identity.service;

import com.nest.app.identity.dto.UserProfileResponse;
import com.nest.app.identity.dto.UserSearchResult;
import com.nest.app.identity.entity.ThemePreference;
import com.nest.app.identity.entity.User;
import com.nest.app.identity.repository.RefreshTokenRepository;
import com.nest.app.identity.repository.UserRepository;
import com.nest.app.storage.FileStorageService;
import com.nest.common.audit.Auditable;
import com.nest.app.identity.dto.NotificationPrefsDto;
import com.nest.app.identity.entity.OtpPurpose;
import com.nest.common.exception.BadRequestException;
import com.nest.common.exception.ResourceNotFoundException;
import com.nest.common.security.TenantContext;
import org.springframework.data.domain.PageRequest;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.multipart.MultipartFile;

import java.util.List;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;

@Service
public class UserService {

    private final UserRepository userRepository;
    private final PrincipalAssembler principalAssembler;
    private final PasswordEncoder passwordEncoder;
    private final TempPasswordGenerator tempPasswordGenerator;
    private final RefreshTokenRepository refreshTokenRepository;
    private final FileStorageService fileStorageService;
    private final OtpService otpService;

    public UserService(UserRepository userRepository, PrincipalAssembler principalAssembler, PasswordEncoder passwordEncoder,
                        TempPasswordGenerator tempPasswordGenerator, RefreshTokenRepository refreshTokenRepository,
                        FileStorageService fileStorageService, OtpService otpService) {
        this.otpService = otpService;
        this.userRepository = userRepository;
        this.principalAssembler = principalAssembler;
        this.passwordEncoder = passwordEncoder;
        this.tempPasswordGenerator = tempPasswordGenerator;
        this.refreshTokenRepository = refreshTokenRepository;
        this.fileStorageService = fileStorageService;
    }

    /** Social "Search" tab - up to 20 matches, name/photo only (no PII). Blank/short queries
     * return nothing rather than the whole user table. */
    @Transactional(readOnly = true)
    public List<UserSearchResult> search(String query) {
        String q = query == null ? "" : query.trim();
        if (q.length() < 2) {
            return List.of();
        }
        return userRepository.findByUsernameContainingIgnoreCaseOrFullNameContainingIgnoreCase(q, q, PageRequest.of(0, 20))
                .stream()
                .map(u -> new UserSearchResult(u.getId(), u.getUsername(), u.getFullName(), u.getProfileImageUrl()))
                .collect(Collectors.toList());
    }

    @Transactional(readOnly = true)
    public UserProfileResponse getProfile(UUID userId) {
        User user = userRepository.findById(userId).orElseThrow(() -> new ResourceNotFoundException("User not found"));
        UUID activeMembershipId = TenantContext.get() != null ? TenantContext.get().activeMembershipId() : null;

        return new UserProfileResponse(
                user.getId(), user.getUsername(), user.getFullName(), maskPhone(user.getPhone()), user.getEmail(),
                user.getCity(), user.getState(), user.getRole(), user.isTemporaryPassword(), user.getThemePreference(), user.getLanguagePreference(),
                principalAssembler.summarise(user), activeMembershipId, user.getProfileImageUrl()
        );
    }

    /** Called right after a Student/Trainer is registered (PRD 3.4/3.5's "upload a photo" step) -
     * gated by the same registration features, not by "self", since the person setting the photo
     * is the Admin/Trainer doing the registering, not the student themself (they're often OTP-only
     * accounts with no session of their own yet). */
    @Transactional
    @Auditable(action = "PROFILE_IMAGE_UPDATED", entityType = "user")
    public UserProfileResponse updateProfileImage(UUID userId, MultipartFile file) {
        User user = userRepository.findById(userId).orElseThrow(() -> new ResourceNotFoundException("User not found"));
        String url = fileStorageService.store(file, "profile-images",
                Set.of("image/jpeg", "image/png", "image/webp"), 5L * 1024 * 1024);
        user.setProfileImageUrl(url);
        userRepository.save(user);
        return getProfile(userId);
    }

    @Transactional
    public void updateThemePreference(UUID userId, ThemePreference preference) {
        User user = userRepository.findById(userId).orElseThrow(() -> new ResourceNotFoundException("User not found"));
        user.setThemePreference(preference);
        userRepository.save(user);
    }

    @Transactional(readOnly = true)
    public NotificationPrefsDto notificationPrefs(UUID userId) {
        User u = userRepository.findById(userId).orElseThrow(() -> new ResourceNotFoundException("User not found"));
        return new NotificationPrefsDto(u.isNotifyAttendance(), u.isNotifyEvents(), u.isNotifyStudy());
    }

    @Transactional
    public NotificationPrefsDto updateNotificationPrefs(UUID userId, NotificationPrefsDto prefs) {
        User u = userRepository.findById(userId).orElseThrow(() -> new ResourceNotFoundException("User not found"));
        u.setNotifyAttendance(prefs.attendance());
        u.setNotifyEvents(prefs.events());
        u.setNotifyStudy(prefs.study());
        userRepository.save(u);
        return prefs;
    }

    /** Step 1 of changing the login email: send a code to the NEW address. The address must not
     * already belong to someone else. */
    @Transactional
    public void requestEmailChange(UUID userId, String newEmail) {
        String email = newEmail.trim();
        userRepository.findByEmailIgnoreCase(email).filter(o -> !o.getId().equals(userId)).ifPresent(o -> {
            throw new BadRequestException("That email is already used by another account");
        });
        otpService.requestOtpForEmail(email, OtpPurpose.EMAIL_CHANGE, userId);
    }

    /** Step 2: the code proves the caller can read mail at the new address; only then is it saved. */
    @Transactional
    public void confirmEmailChange(UUID userId, String newEmail, String code) {
        String email = newEmail.trim();
        UUID ctx = otpService.verifyOtpForEmail(email, code, OtpPurpose.EMAIL_CHANGE);
        if (!userId.equals(ctx)) {
            throw new BadRequestException("That code was not issued for this account");
        }
        User u = userRepository.findById(userId).orElseThrow(() -> new ResourceNotFoundException("User not found"));
        u.setEmail(email);
        userRepository.save(u);
    }

    @Transactional
    public void updateLanguagePreference(UUID userId, String languageTag) {
        User user = userRepository.findById(userId).orElseThrow(() -> new ResourceNotFoundException("User not found"));
        user.setLanguagePreference(languageTag);
        userRepository.save(user);
    }

    /**
     * Super-Admin-only escape hatch for exactly the situation that prompted it: a temporary
     * password (shown once at creation, per PRD 3.2/3.5) got lost before anyone wrote it down.
     * Only meaningful for password-holding accounts (Admin/Trainer) - Students/Guests are
     * OTP-only and have no password to reset. Also revokes every existing session for that user,
     * same as a self-service password change (com.nest.app.identity.service.AuthService#changePassword) -
     * a reset should not leave old sessions usable.
     */
    @Transactional
    @Auditable(action = "PASSWORD_RESET_BY_ADMIN", entityType = "user")
    public String resetPasswordByUsername(String username) {
        User user = userRepository.findByUsername(username)
                .orElseThrow(() -> new ResourceNotFoundException("No user found with username: " + username));
        return resetPassword(user);
    }

    private String resetPassword(User user) {
        if (user.getPasswordHash() == null) {
            throw new BadRequestException("This account uses OTP login and has no password to reset");
        }

        String tempPassword = tempPasswordGenerator.generate();
        user.setPasswordHash(passwordEncoder.encode(tempPassword));
        user.setTemporaryPassword(true);
        userRepository.save(user);

        refreshTokenRepository.revokeAllForUser(user.getId());

        return tempPassword;
    }

    private String maskPhone(String phone) {
        if (phone == null || phone.length() < 4) {
            return phone;
        }
        int visibleTail = 2;
        return "x".repeat(phone.length() - visibleTail) + phone.substring(phone.length() - visibleTail);
    }
}
