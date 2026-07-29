package com.nest.app.platform.service;

import com.nest.app.identity.repository.UserRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

import java.time.Duration;
import java.time.Instant;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Stamps {@code users.last_seen_at} so the Super Admin console can answer "who's active right
 * now / today / this week".
 *
 * <p>Writing on every authenticated request would mean a DB write per request, which is a real
 * cost for a metric that only needs hour-level resolution. So writes are throttled per user
 * in-memory: at most one every {@link #WRITE_THROTTLE}. The map is a deliberate accept-the-loss
 * cache - it's per-instance and cleared on restart, which at worst causes one extra write per user
 * after a deploy. It's bounded by re-checking the timestamp rather than growing forever, and the
 * entry per active user is a UUID plus an Instant, so even a large active set is trivial.
 */
@Service
public class ActivityTracker {

    private static final Logger log = LoggerFactory.getLogger(ActivityTracker.class);
    private static final Duration WRITE_THROTTLE = Duration.ofMinutes(5);

    private final UserRepository userRepository;
    private final Map<UUID, Instant> lastWrittenAt = new ConcurrentHashMap<>();

    public ActivityTracker(UserRepository userRepository) {
        this.userRepository = userRepository;
    }

    /**
     * Never lets a tracking failure break the actual request - this runs on the hot path of every
     * authenticated call, and a metric is not worth failing a user's request over. REQUIRES_NEW so
     * it can't mark a caller's transaction rollback-only either.
     */
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void recordSeen(UUID userId) {
        Instant now = Instant.now();
        Instant previous = lastWrittenAt.get(userId);
        if (previous != null && previous.isAfter(now.minus(WRITE_THROTTLE))) {
            return;
        }
        lastWrittenAt.put(userId, now);
        try {
            userRepository.touchLastSeen(userId, now);
        } catch (RuntimeException ex) {
            log.debug("Could not record last_seen_at for user {}", userId, ex);
        }
    }
}
