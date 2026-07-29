package com.nest.app.platform.service;

import com.nest.app.academy.entity.Academy;
import com.nest.app.academy.repository.AcademyRepository;
import com.nest.app.curriculum.entity.CourseStatus;
import com.nest.app.curriculum.repository.CourseRepository;
import com.nest.app.enrolment.repository.BatchRepository;
import com.nest.app.event.repository.EventRepository;
import com.nest.app.fees.repository.FeeTransactionRepository;
import com.nest.app.identity.entity.MembershipStatus;
import com.nest.app.identity.repository.AcademyMembershipRepository;
import com.nest.app.platform.dto.AcademyStatsResponse;
import com.nest.app.social.repository.PostRepository;
import com.nest.common.exception.ResourceNotFoundException;
import com.nest.common.security.Role;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

/**
 * Per-academy counts for the Super Admin console (PRD 2.4). Read-only by design: the console can
 * see everything about a tenant but does not edit its operational data - fee and attendance rows
 * are the academy's own business records, and a platform operator silently changing them would
 * make those records unusable in a dispute. Lifecycle actions (suspend, plan) live on
 * AcademyController instead.
 *
 * <p>Every count is fetched with ONE grouped query covering all academies, then joined in memory.
 * The obvious alternative - loop the academies and count each - is a handful of queries per
 * academy, so it degrades linearly with tenant count exactly as the platform grows.
 */
@Service
public class AcademyStatsService {

    private final AcademyRepository academyRepository;
    private final AcademyMembershipRepository membershipRepository;
    private final CourseRepository courseRepository;
    private final BatchRepository batchRepository;
    private final EventRepository eventRepository;
    private final PostRepository postRepository;
    private final FeeTransactionRepository feeTransactionRepository;

    public AcademyStatsService(AcademyRepository academyRepository, AcademyMembershipRepository membershipRepository,
                               CourseRepository courseRepository, BatchRepository batchRepository,
                               EventRepository eventRepository, PostRepository postRepository,
                               FeeTransactionRepository feeTransactionRepository) {
        this.academyRepository = academyRepository;
        this.membershipRepository = membershipRepository;
        this.courseRepository = courseRepository;
        this.batchRepository = batchRepository;
        this.eventRepository = eventRepository;
        this.postRepository = postRepository;
        this.feeTransactionRepository = feeTransactionRepository;
    }

    @Transactional(readOnly = true)
    public List<AcademyStatsResponse> listAll() {
        Counts counts = loadCounts();
        List<AcademyStatsResponse> result = new ArrayList<>();
        for (Academy academy : academyRepository.findAll()) {
            result.add(toResponse(academy, counts));
        }
        // Biggest tenants first - that's the order a platform operator scans in.
        result.sort(Comparator.comparingLong(AcademyStatsResponse::students).reversed());
        return result;
    }

    @Transactional(readOnly = true)
    public AcademyStatsResponse detail(UUID academyId) {
        Academy academy = academyRepository.findById(academyId)
                .orElseThrow(() -> new ResourceNotFoundException("Academy not found: " + academyId));
        return toResponse(academy, loadCounts());
    }

    private AcademyStatsResponse toResponse(Academy academy, Counts counts) {
        UUID id = academy.getId();
        return new AcademyStatsResponse(
                id,
                academy.getName(),
                academy.getCity(),
                academy.getStatus().name(),
                academy.getPlan(),
                academy.getCreatedAt(),
                counts.lastActivity.get(id),
                counts.byRole.getOrDefault(roleKey(id, Role.STUDENT), 0L),
                counts.byRole.getOrDefault(roleKey(id, Role.TRAINER), 0L),
                counts.byRole.getOrDefault(roleKey(id, Role.ACADEMY_ADMIN), 0L),
                counts.courses.getOrDefault(id, 0L),
                counts.batches.getOrDefault(id, 0L),
                counts.events.getOrDefault(id, 0L),
                counts.posts.getOrDefault(id, 0L),
                counts.fees.getOrDefault(id, BigDecimal.ZERO));
    }

    private Counts loadCounts() {
        Counts counts = new Counts();
        for (Object[] row : membershipRepository.countByAcademyAndRole(MembershipStatus.ACTIVE)) {
            counts.byRole.put(roleKey((UUID) row[0], (Role) row[1]), ((Number) row[2]).longValue());
        }
        for (Object[] row : membershipRepository.lastActivityByAcademy(MembershipStatus.ACTIVE)) {
            if (row[1] != null) {
                counts.lastActivity.put((UUID) row[0], (Instant) row[1]);
            }
        }
        putLongs(counts.courses, courseRepository.countByAcademyGrouped(CourseStatus.ACTIVE));
        putLongs(counts.batches, batchRepository.countByAcademyGrouped());
        putLongs(counts.events, eventRepository.countByAcademyGrouped());
        putLongs(counts.posts, postRepository.countByAcademyGrouped());
        for (Object[] row : feeTransactionRepository.sumCollectedByAcademyGrouped()) {
            counts.fees.put((UUID) row[0], (BigDecimal) row[1]);
        }
        return counts;
    }

    private void putLongs(Map<UUID, Long> target, List<Object[]> rows) {
        for (Object[] row : rows) {
            target.put((UUID) row[0], ((Number) row[1]).longValue());
        }
    }

    private String roleKey(UUID academyId, Role role) {
        return academyId + "|" + role.name();
    }

    /** Plain holder so loadCounts() can return all six lookups without six parameters. */
    private static final class Counts {
        final Map<String, Long> byRole = new HashMap<>();
        final Map<UUID, Instant> lastActivity = new HashMap<>();
        final Map<UUID, Long> courses = new HashMap<>();
        final Map<UUID, Long> batches = new HashMap<>();
        final Map<UUID, Long> events = new HashMap<>();
        final Map<UUID, Long> posts = new HashMap<>();
        final Map<UUID, BigDecimal> fees = new HashMap<>();
    }
}
