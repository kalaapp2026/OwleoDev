package com.nest.identity.dto;

public record AuthResponse(
        String accessToken,
        String refreshToken,
        String tokenType,
        long expiresInSeconds,
        UserProfileResponse user
) {
    public static AuthResponse of(String accessToken, String refreshToken, long expiresInSeconds, UserProfileResponse user) {
        return new AuthResponse(accessToken, refreshToken, "Bearer", expiresInSeconds, user);
    }
}
