package com.nest.app.platform.service;

import com.nest.app.academy.entity.AcademyStatus;
import com.nest.app.academy.repository.AcademyRepository;
import com.nest.app.event.repository.EventRepository;
import com.nest.app.identity.entity.ArtistApplicationStatus;
import com.nest.app.identity.repository.ArtistApplicationRepository;
import com.nest.app.identity.repository.UserRepository;
import com.nest.app.platform.dto.PlatformOverviewResponse;
import com.nest.app.platform.repository.DeviceInstallRepository;
import com.nest.app.social.repository.PostRepository;
import com.nest.common.security.Role;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.sql.Timestamp;
import java.time.Duration;
import java.time.Instant;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Cross-tenant analytics for the Super Admin console (PRD 2.4). Every query here deliberately
 * spans ALL academies, which is the exact opposite of the tenant-scoping rule the rest of the app
 * follows - that's only safe because the single caller, {@code PlatformMetricsController}, is
 * locked to SUPER_ADMIN, and because everything returned is an aggregate count rather than any
 * individual academy's records.
 */
@Service
public class PlatformMetricsService {

    private static final int SIGNUP_TREND_DAYS = 30;

    private final AcademyRepository academyRepository;
    private final UserRepository userRepository;
    private final PostRepository postRepository;
    private final EventRepository eventRepository;
    private final ArtistApplicationRepository artistApplicationRepository;
    private final DeviceInstallRepository deviceInstallRepository;

    public PlatformMetricsService(AcademyRepository academyRepository, UserRepository userRepository,
                                  PostRepository postRepository, EventRepository eventRepository,
                                  ArtistApplicationRepository artistApplicationRepository,
                                  DeviceInstallRepository deviceInstallRepository) {
        this.academyRepository = academyRepository;
        this.userRepository = userRepository;
        this.postRepository = postRepository;
        this.eventRepository = eventRepository;
        this.artistApplicationRepository = artistApplicationRepository;
        this.deviceInstallRepository = deviceInstallRepository;
    }

    @Transactional(readOnly = true)
    public PlatformOverviewResponse overview() {
        Instant now = Instant.now();
        Instant hourAgo = now.minus(Duration.ofHours(1));
        Instant dayAgo = now.minus(Duration.ofDays(1));
        Instant weekAgo = now.minus(Duration.ofDays(7));
        Instant monthAgo = now.minus(Duration.ofDays(30));

        var academies = new PlatformOverviewResponse.AcademyStats(
                academyRepository.count(),
                academyRepository.countByStatus(AcademyStatus.ACTIVE),
                academyRepository.countByStatus(AcademyStatus.SUSPENDED),
                academyRepository.countByCreatedAtAfter(monthAgo));

        Map<String, Long> byRole = new LinkedHashMap<>();
        for (Role role : Role.values()) {
            byRole.put(role.name(), userRepository.countByRole(role));
        }
        var users = new PlatformOverviewResponse.UserStats(
                userRepository.count(), byRole,
                userRepository.countByCreatedAtAfter(weekAgo),
                userRepository.countByCreatedAtAfter(monthAgo));

        var activity = new PlatformOverviewResponse.ActivityStats(
                userRepository.countByLastSeenAtAfter(hourAgo),
                userRepository.countByLastSeenAtAfter(dayAgo),
                userRepository.countByLastSeenAtAfter(weekAgo),
                userRepository.countByLastSeenAtAfter(monthAgo),
                deviceInstallRepository.count());

        var social = new PlatformOverviewResponse.SocialStats(
                postRepository.count(),
                postRepository.countByCreatedAtAfter(weekAgo),
                eventRepository.count(),
                eventRepository.countByEventDateAfter(LocalDateTime.now()),
                artistApplicationRepository.findByStatusOrderByCreatedAtAsc(ArtistApplicationStatus.PENDING).size());

        return new PlatformOverviewResponse(academies, users, activity, social, signupTrend(now));
    }

    /**
     * Signups per day for the last {@value #SIGNUP_TREND_DAYS} days. Days with no signups are
     * filled in as zero rather than omitted - a line chart that silently skips empty days draws a
     * misleadingly smooth line between two distant points.
     */
    private List<PlatformOverviewResponse.DailyCount> signupTrend(Instant now) {
        LocalDate today = LocalDate.ofInstant(now, ZoneOffset.UTC);
        LocalDate from = today.minusDays(SIGNUP_TREND_DAYS - 1L);

        Map<LocalDate, Long> counts = new LinkedHashMap<>();
        for (Object[] row : userRepository.countSignupsPerDaySince(from.atStartOfDay().toInstant(ZoneOffset.UTC))) {
            counts.put(toLocalDate(row[0]), ((Number) row[1]).longValue());
        }

        List<PlatformOverviewResponse.DailyCount> trend = new ArrayList<>(SIGNUP_TREND_DAYS);
        for (LocalDate day = from; !day.isAfter(today); day = day.plusDays(1)) {
            trend.add(new PlatformOverviewResponse.DailyCount(day, counts.getOrDefault(day, 0L)));
        }
        return trend;
    }

    /** date_trunc comes back as a java.sql.Timestamp on Postgres, but the exact type isn't
     * guaranteed across drivers, so handle the reasonable shapes rather than blind-casting. */
    private LocalDate toLocalDate(Object value) {
        if (value instanceof Timestamp timestamp) {
            return timestamp.toLocalDateTime().toLocalDate();
        }
        if (value instanceof Instant instant) {
            return LocalDate.ofInstant(instant, ZoneOffset.UTC);
        }
        if (value instanceof LocalDateTime dateTime) {
            return dateTime.toLocalDate();
        }
        return LocalDate.parse(value.toString().substring(0, 10));
    }
}
