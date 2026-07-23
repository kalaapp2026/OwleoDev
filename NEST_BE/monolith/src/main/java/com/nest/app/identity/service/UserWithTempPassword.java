package com.nest.app.identity.service;

import com.nest.app.identity.entity.User;

public record UserWithTempPassword(User user, String temporaryPassword) {
}
