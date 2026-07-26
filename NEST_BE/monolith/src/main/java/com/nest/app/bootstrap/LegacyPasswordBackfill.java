package com.nest.app.bootstrap;

import com.nest.app.identity.entity.User;
import com.nest.app.identity.repository.UserRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.core.annotation.Order;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Component;

import java.util.List;

/**
 * Unified login (all roles use username + password) left the pre-existing OTP-only accounts
 * (Students/Guests/Artists created before the switch) with no password, so they couldn't log in.
 * This one-time backfill gives each such account a temp password equal to its own username, marked
 * temporary so the user is forced to change it on first login. Idempotent: once an account has a
 * password it's never touched again, so this simply does nothing on every subsequent boot.
 *
 * <p>The username-as-temp-password is a dev-stage convenience (admin can tell the person "your
 * temporary password is your username"); for anything real, use the Admin "reset password" action
 * to issue a strong one instead.
 */
@Component
@Order(100)
public class LegacyPasswordBackfill implements ApplicationRunner {

    private static final Logger log = LoggerFactory.getLogger(LegacyPasswordBackfill.class);

    private final UserRepository userRepository;
    private final PasswordEncoder passwordEncoder;

    public LegacyPasswordBackfill(UserRepository userRepository, PasswordEncoder passwordEncoder) {
        this.userRepository = userRepository;
        this.passwordEncoder = passwordEncoder;
    }

    @Override
    public void run(ApplicationArguments args) {
        List<User> passwordless = userRepository.findByPasswordHashIsNull();
        if (passwordless.isEmpty()) {
            return;
        }
        passwordless.forEach(user -> {
            user.setPasswordHash(passwordEncoder.encode(user.getUsername()));
            user.setTemporaryPassword(true);
        });
        userRepository.saveAll(passwordless);
        log.warn("""

                ================================================================
                UNIFIED LOGIN BACKFILL: {} legacy OTP-only account(s) given a temp password.
                Each temp password = that account's own username (change on first login).
                Use the Admin "reset password" action to issue a strong one.
                ================================================================""",
                passwordless.size());
    }
}
