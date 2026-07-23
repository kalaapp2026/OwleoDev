package com.nest.app.identity.dto;

public record PasswordResetResponse(String username, String temporaryPassword) {
}
