package com.nest.app.bootstrap;

import com.nest.app.identity.entity.User;
import com.nest.app.identity.repository.UserRepository;
import com.nest.common.crypto.PiiHasher;
import com.nest.common.security.Role;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Component;

/**
 * PRD 2.4: Super Admin is "System (platform owner)" - there's deliberately no API to create one
 * (onboarding an academy REQUIRES being a Super Admin already, so nothing can bootstrap itself).
 * Without this, the very first login on a fresh database is a dead end. Seeds exactly one
 * Super Admin with a fixed, well-known dev password so Swagger/Postman testing has somewhere to
 * start. Gated by a property (default on) so it's a one-line disable for anything but local dev.
 */
@Component
public class DevSuperAdminSeeder implements ApplicationRunner {

    private static final Logger log = LoggerFactory.getLogger(DevSuperAdminSeeder.class);

    private static final String USERNAME = "superadmin";
    private static final String PASSWORD = "SuperAdmin@123";
    private static final String PHONE = "9000000000";

    private final UserRepository userRepository;
    private final PiiHasher hasher;
    private final PasswordEncoder passwordEncoder;
    private final boolean enabled;

    public DevSuperAdminSeeder(UserRepository userRepository, PiiHasher hasher, PasswordEncoder passwordEncoder,
                                @Value("${nest.dev-seed.enabled:true}") boolean enabled) {
        this.userRepository = userRepository;
        this.hasher = hasher;
        this.passwordEncoder = passwordEncoder;
        this.enabled = enabled;
    }

    @Override
    public void run(ApplicationArguments args) {
        if (!enabled || userRepository.existsByUsername(USERNAME)) {
            return;
        }

        User superAdmin = User.builder()
                .username(USERNAME)
                .fullName("Platform Owner")
                .phone(PHONE)
                .phoneHash(hasher.hash(PHONE))
                .email("superadmin@nest.dev")
                .role(Role.SUPER_ADMIN)
                .passwordHash(passwordEncoder.encode(PASSWORD))
                .temporaryPassword(false)
                .build();
        userRepository.save(superAdmin);

        log.warn("""

                ================================================================
                DEV SEED: Super Admin account created (nest.dev-seed.enabled=true)
                  username: {}
                  password: {}
                Disable via nest.dev-seed.enabled=false before anything but local dev.
                ================================================================""",
                USERNAME, PASSWORD);
    }
}
