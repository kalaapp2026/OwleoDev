package com.nest.identity.service;

import com.nest.common.exception.ResourceNotFoundException;
import com.nest.common.security.TenantContext;
import com.nest.identity.dto.UserProfileResponse;
import com.nest.identity.entity.ThemePreference;
import com.nest.identity.entity.User;
import com.nest.identity.repository.UserRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.UUID;

@Service
public class UserService {

    private final UserRepository userRepository;
    private final PrincipalAssembler principalAssembler;

    public UserService(UserRepository userRepository, PrincipalAssembler principalAssembler) {
        this.userRepository = userRepository;
        this.principalAssembler = principalAssembler;
    }

    @Transactional(readOnly = true)
    public UserProfileResponse getProfile(UUID userId) {
        User user = userRepository.findById(userId).orElseThrow(() -> new ResourceNotFoundException("User not found"));
        UUID activeMembershipId = TenantContext.get() != null ? TenantContext.get().activeMembershipId() : null;

        return new UserProfileResponse(
                user.getId(), user.getUsername(), user.getFullName(), maskPhone(user.getPhone()), user.getEmail(),
                user.getCity(), user.getState(), user.getRole(), user.isTemporaryPassword(), user.getThemePreference(),
                principalAssembler.summarise(user), activeMembershipId
        );
    }

    @Transactional
    public void updateThemePreference(UUID userId, ThemePreference preference) {
        User user = userRepository.findById(userId).orElseThrow(() -> new ResourceNotFoundException("User not found"));
        user.setThemePreference(preference);
        userRepository.save(user);
    }

    private String maskPhone(String phone) {
        if (phone == null || phone.length() < 4) {
            return phone;
        }
        int visibleTail = 2;
        return "x".repeat(phone.length() - visibleTail) + phone.substring(phone.length() - visibleTail);
    }
}
