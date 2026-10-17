package com.nest.app.notification.service;

import com.nest.app.notification.entity.PushDeviceToken;
import com.nest.app.notification.repository.PushDeviceTokenRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.util.UUID;

@Service
public class PushTokenService {

    private final PushDeviceTokenRepository repository;

    public PushTokenService(PushDeviceTokenRepository repository) {
        this.repository = repository;
    }

    /** A token belongs to one person at a time: if the phone changed hands (sign out, someone else
     * signs in), the row is re-pointed rather than duplicated, so alerts follow the current user. */
    @Transactional
    public void register(UUID userId, String token, String platform) {
        PushDeviceToken row = repository.findByToken(token)
                .orElseGet(() -> PushDeviceToken.builder().token(token).build());
        row.setUserId(userId);
        row.setPlatform(platform);
        row.setLastSeenAt(Instant.now());
        repository.save(row);
    }

    /** Only removes the caller's own token - someone else's can't be unregistered by guessing it. */
    @Transactional
    public void unregister(UUID userId, String token) {
        repository.findByToken(token)
                .filter(t -> t.getUserId().equals(userId))
                .ifPresent(repository::delete);
    }
}
