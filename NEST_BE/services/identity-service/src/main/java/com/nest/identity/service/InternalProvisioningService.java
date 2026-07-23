package com.nest.identity.service;

import com.nest.common.audit.Auditable;
import com.nest.common.crypto.PiiHasher;
import com.nest.common.exception.ConflictException;
import com.nest.common.security.Role;
import com.nest.identity.dto.ProvisionAcademyAdminRequest;
import com.nest.identity.dto.ProvisionAcademyAdminResponse;
import com.nest.identity.entity.AcademyMembership;
import com.nest.identity.entity.MembershipStatus;
import com.nest.identity.entity.User;
import com.nest.identity.repository.AcademyMembershipRepository;
import com.nest.identity.repository.UserRepository;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.security.SecureRandom;

/**
 * Called only by academy-service over the internal API-key-protected channel (see
 * InternalApiKeyFilter) when a Super Admin onboards a new academy (PRD 3.2).
 */
@Service
public class InternalProvisioningService {

    private static final String TEMP_PASSWORD_CHARS = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789";
    private static final int TEMP_PASSWORD_LENGTH = 12;

    private final UserRepository userRepository;
    private final AcademyMembershipRepository membershipRepository;
    private final PiiHasher hasher;
    private final PasswordEncoder passwordEncoder;
    private final SecureRandom random = new SecureRandom();

    public InternalProvisioningService(UserRepository userRepository, AcademyMembershipRepository membershipRepository,
                                        PiiHasher hasher, PasswordEncoder passwordEncoder) {
        this.userRepository = userRepository;
        this.membershipRepository = membershipRepository;
        this.hasher = hasher;
        this.passwordEncoder = passwordEncoder;
    }

    @Transactional
    @Auditable(action = "ACADEMY_ADMIN_PROVISIONED", entityType = "user")
    public ProvisionAcademyAdminResponse provisionAcademyAdmin(ProvisionAcademyAdminRequest request) {
        if (userRepository.existsByUsername(request.username())) {
            throw new ConflictException("Username already taken: " + request.username());
        }
        String phoneHash = hasher.hash(request.phone());
        if (userRepository.existsByPhoneHash(phoneHash)) {
            throw new ConflictException(
                    "This phone number already has a NEST account. Provisioning a new Academy Admin requires a fresh " +
                    "phone number for Phase 1 - linking an existing person as an Admin of a second academy is not yet supported.");
        }

        String tempPassword = generateTempPassword();

        User user = User.builder()
                .username(request.username())
                .fullName(request.fullName())
                .phone(request.phone())
                .phoneHash(phoneHash)
                .email(request.email())
                .role(Role.ACADEMY_ADMIN)
                .passwordHash(passwordEncoder.encode(tempPassword))
                .temporaryPassword(true)
                .build();
        user = userRepository.save(user);

        AcademyMembership membership = AcademyMembership.builder()
                .userId(user.getId())
                .academyId(request.academyId())
                .academyName(request.academyName())
                .roleType(Role.ACADEMY_ADMIN)
                .status(MembershipStatus.ACTIVE)
                .build();
        membership = membershipRepository.save(membership);

        return new ProvisionAcademyAdminResponse(user.getId(), membership.getId(), user.getUsername(), tempPassword);
    }

    private String generateTempPassword() {
        StringBuilder sb = new StringBuilder(TEMP_PASSWORD_LENGTH);
        for (int i = 0; i < TEMP_PASSWORD_LENGTH; i++) {
            sb.append(TEMP_PASSWORD_CHARS.charAt(random.nextInt(TEMP_PASSWORD_CHARS.length())));
        }
        return sb.toString();
    }
}
