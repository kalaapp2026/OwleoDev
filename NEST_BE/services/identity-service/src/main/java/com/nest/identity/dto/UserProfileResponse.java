package com.nest.identity.dto;

import com.nest.common.security.Role;
import com.nest.identity.entity.ThemePreference;

import java.util.List;
import java.util.UUID;

public record UserProfileResponse(
        UUID id,
        String username,
        String fullName,
        String maskedPhone,
        String email,
        String city,
        String state,
        Role role,
        boolean temporaryPassword,
        ThemePreference themePreference,
        List<MembershipSummary> memberships,
        UUID activeMembershipId
) {
}
