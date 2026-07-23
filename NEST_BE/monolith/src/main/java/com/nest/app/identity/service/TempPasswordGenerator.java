package com.nest.app.identity.service;

import org.springframework.stereotype.Component;

/** Shared by initial provisioning (IdentityRegistrationService) and admin-triggered resets
 * (UserService.resetPassword) so both produce passwords with the same strength/character set. */
@Component
public class TempPasswordGenerator {

    // DEV-ONLY: fixed so manual testing doesn't require reading a generated password out of the
    // API response every time. Swap back to random generation before this goes anywhere real.
    private static final String DEV_FIXED_PASSWORD = "Nest@123";

    public String generate() {
        return DEV_FIXED_PASSWORD;
    }
}
