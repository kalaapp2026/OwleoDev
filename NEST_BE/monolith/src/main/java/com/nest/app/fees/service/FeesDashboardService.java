package com.nest.app.fees.service;

import com.nest.app.curriculum.entity.Course;
import com.nest.app.curriculum.repository.CourseRepository;
import com.nest.app.enrolment.entity.Batch;
import com.nest.app.enrolment.entity.BatchMember;
import com.nest.app.enrolment.repository.BatchMemberRepository;
import com.nest.app.enrolment.repository.BatchRepository;
import com.nest.app.fees.dto.FeeSummaryResponse;
import com.nest.app.fees.dto.StudentSearchResult;
import com.nest.app.fees.entity.FeeCategory;
import com.nest.app.fees.entity.FeeMode;
import com.nest.app.fees.entity.FeeSlip;
import com.nest.app.fees.entity.FeeTransaction;
import com.nest.app.fees.entity.FeeType;
import com.nest.app.fees.entity.FeeTypeBatch;
import com.nest.app.fees.repository.FeeSlipRepository;
import com.nest.app.fees.repository.FeeTransactionRepository;
import com.nest.app.fees.repository.FeeTypeBatchRepository;
import com.nest.app.fees.repository.FeeTypeRepository;
import com.nest.app.identity.entity.AcademyMembership;
import com.nest.app.identity.entity.CourseMap;
import com.nest.app.identity.entity.MembershipStatus;
import com.nest.app.identity.entity.User;
import com.nest.app.identity.repository.AcademyMembershipRepository;
import com.nest.app.identity.repository.CourseMapRepository;
import com.nest.app.identity.repository.UserRepository;
import com.nest.common.security.Role;
import com.nest.common.security.TenantContext;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;

/**
 * The fees landing: how much each category has collected, and a search across every student.
 *
 * <p>Its own service because it reads across both halves of the module and owns neither.</p>
 */
@Service
public class FeesDashboardService {

    private final CourseRepository courseRepository;
    private final CourseMapRepository courseMapRepository;
    private final FeeSlipRepository feeSlipRepository;
    private final FeeTransactionRepository feeTransactionRepository;
    private final FeeTypeRepository feeTypeRepository;
    private final FeeTypeBatchRepository feeTypeBatchRepository;
    private final BatchRepository batchRepository;
    private final BatchMemberRepository batchMemberRepository;
    private final AcademyMembershipRepository membershipRepository;
    private final UserRepository userRepository;

    public FeesDashboardService(CourseRepository courseRepository,
                                CourseMapRepository courseMapRepository,
                                FeeSlipRepository feeSlipRepository,
                                FeeTransactionRepository feeTransactionRepository,
                                FeeTypeRepository feeTypeRepository,
                                FeeTypeBatchRepository feeTypeBatchRepository,
                                BatchRepository batchRepository,
                                BatchMemberRepository batchMemberRepository,
                                AcademyMembershipRepository membershipRepository,
                                UserRepository userRepository) {
        this.courseRepository = courseRepository;
        this.courseMapRepository = courseMapRepository;
        this.feeSlipRepository = feeSlipRepository;
        this.feeTransactionRepository = feeTransactionRepository;
        this.feeTypeRepository = feeTypeRepository;
        this.feeTypeBatchRepository = feeTypeBatchRepository;
        this.batchRepository = batchRepository;
        this.batchMemberRepository = batchMemberRepository;
        this.membershipRepository = membershipRepository;
        this.userRepository = userRepository;
    }

    /**
     * Both categories' position, optionally narrowed to one course and/or batch.
     *
     * <p>The regular half is scoped to a billing period; the other half is not, because an Other
     * fee has no period - a costume fee is raised once and stays outstanding until paid, whatever
     * month you happen to be looking at.</p>
     */
    @Transactional(readOnly = true)
    public FeeSummaryResponse summary(String period, UUID courseId, UUID batchId) {
        UUID academyId = TenantContext.currentAcademyId();
        return new FeeSummaryResponse(
                regularSummary(academyId, period, courseId, batchId),
                otherSummary(academyId, courseId, batchId));
    }

    private FeeSummaryResponse.CategorySummary regularSummary(
            UUID academyId, String period, UUID courseId, UUID batchId) {

        List<Course> courses = courseRepository.findByAcademyId(academyId).stream()
                .filter(c -> courseId == null || c.getId().equals(courseId))
                .toList();
        if (courses.isEmpty()) {
            return FeeSummaryResponse.CategorySummary.empty();
        }
        List<UUID> courseIds = courses.stream().map(Course::getId).toList();

        // When a batch is named, only its members count - the card must agree with the roster the
        // admin would open next.
        Set<UUID> batchMemberIds = batchId == null ? null
                : batchMemberRepository.findByBatchId(batchId).stream()
                        .map(BatchMember::getMembershipId).collect(Collectors.toSet());

        List<CourseMap> enrolments = courseMapRepository.findByCourseIdIn(courseIds).stream()
                .filter(CourseMap::isActive)
                .filter(cm -> cm.getAgreedFee() != null)
                .filter(cm -> batchMemberIds == null || batchMemberIds.contains(cm.getMembershipId()))
                .toList();
        if (enrolments.isEmpty()) {
            return FeeSummaryResponse.CategorySummary.empty();
        }

        // Only active students. An archived membership still has a course_map row, and counting it
        // would inflate what the academy appears to be owed.
        Set<UUID> activeStudents = membershipRepository.findAllById(
                        enrolments.stream().map(CourseMap::getMembershipId).collect(Collectors.toSet()))
                .stream()
                .filter(m -> m.getRoleType() == Role.STUDENT && m.getStatus() == MembershipStatus.ACTIVE)
                .map(AcademyMembership::getId)
                .collect(Collectors.toSet());

        // A generated slip's amountDue wins over the flat agreed fee, matching every other screen.
        Map<String, BigDecimal> dueBySlipKey = feeSlipRepository
                .findByCourseIdInAndPeriod(courseIds, period).stream()
                .collect(Collectors.toMap(
                        s -> s.getMembershipId() + "|" + s.getCourseId(),
                        FeeSlip::getAmountDue, (a, b) -> a));

        Map<String, BigDecimal> expectedByEnrolment = new HashMap<>();
        for (CourseMap enrolment : enrolments) {
            if (!activeStudents.contains(enrolment.getMembershipId())) {
                continue;
            }
            String key = enrolment.getMembershipId() + "|" + enrolment.getCourseId();
            expectedByEnrolment.put(key, dueBySlipKey.getOrDefault(key, enrolment.getAgreedFee()));
        }

        Map<String, BigDecimal> paidByEnrolment = new HashMap<>();
        BigDecimal manual = BigDecimal.ZERO;
        BigDecimal gateway = BigDecimal.ZERO;

        for (FeeTransaction tx : feeTransactionRepository
                .findByAcademyIdAndCategoryAndPeriod(academyId, FeeCategory.REGULAR, period)) {
            String key = tx.getMembershipId() + "|" + tx.getCourseId();
            if (!expectedByEnrolment.containsKey(key)) {
                continue;
            }
            paidByEnrolment.merge(key, tx.getAmountPaid(), BigDecimal::add);
            // Reversals are negative, so they subtract from whichever bucket they came from and
            // the split stays consistent with the total without a special case.
            if (tx.getMode() == FeeMode.GATEWAY) {
                gateway = gateway.add(tx.getAmountPaid());
            } else {
                manual = manual.add(tx.getAmountPaid());
            }
        }

        return build(expectedByEnrolment, paidByEnrolment, manual, gateway);
    }

    private FeeSummaryResponse.CategorySummary otherSummary(UUID academyId, UUID courseId, UUID batchId) {
        List<FeeType> types = feeTypeRepository.findByAcademyIdAndActiveTrueOrderByNameAsc(academyId);
        if (types.isEmpty()) {
            return FeeSummaryResponse.CategorySummary.empty();
        }

        Map<UUID, List<FeeTypeBatch>> bindingsByType = feeTypeBatchRepository
                .findByFeeTypeIdIn(types.stream().map(FeeType::getId).toList()).stream()
                .collect(Collectors.groupingBy(FeeTypeBatch::getFeeTypeId));

        Set<UUID> allBatchIds = bindingsByType.values().stream().flatMap(List::stream)
                .map(FeeTypeBatch::getBatchId).collect(Collectors.toSet());
        Map<UUID, Batch> batchesById = batchRepository.findAllById(allBatchIds).stream()
                .collect(Collectors.toMap(Batch::getId, b -> b));

        Map<UUID, Set<UUID>> membersByBatch = new HashMap<>();
        for (UUID id : allBatchIds) {
            membersByBatch.put(id, batchMemberRepository.findByBatchId(id).stream()
                    .map(BatchMember::getMembershipId).collect(Collectors.toSet()));
        }

        Set<UUID> everyMember = membersByBatch.values().stream()
                .flatMap(Set::stream).collect(Collectors.toSet());
        Set<UUID> activeStudents = everyMember.isEmpty() ? Set.of()
                : membershipRepository.findAllById(everyMember).stream()
                        .filter(m -> m.getRoleType() == Role.STUDENT
                                && m.getStatus() == MembershipStatus.ACTIVE)
                        .map(AcademyMembership::getId).collect(Collectors.toSet());

        // One obligation per (student, fee type). A student in two batches that a costume fee
        // applies to still owes the costume fee once, not twice.
        Map<String, BigDecimal> expectedByObligation = new HashMap<>();
        for (FeeType type : types) {
            for (FeeTypeBatch binding : bindingsByType.getOrDefault(type.getId(), List.of())) {
                Batch batch = batchesById.get(binding.getBatchId());
                if (batch == null) {
                    continue;
                }
                if (courseId != null && !batch.getCourseId().equals(courseId)) {
                    continue;
                }
                if (batchId != null && !batch.getId().equals(batchId)) {
                    continue;
                }
                for (UUID membershipId : membersByBatch.getOrDefault(binding.getBatchId(), Set.of())) {
                    if (activeStudents.contains(membershipId)) {
                        expectedByObligation.put(membershipId + "|" + type.getId(), type.getAmount());
                    }
                }
            }
        }

        Map<String, BigDecimal> paidByObligation = new HashMap<>();
        BigDecimal manual = BigDecimal.ZERO;
        BigDecimal gateway = BigDecimal.ZERO;

        for (FeeTransaction tx : feeTransactionRepository
                .findByAcademyIdAndCategory(academyId, FeeCategory.OTHER)) {
            // Per-student one-off fees are deliberately outside this total: they belong to a
            // person, not a batch, so they would make the batch-level figures unexplainable.
            if (tx.getFeeTypeId() == null) {
                continue;
            }
            String key = tx.getMembershipId() + "|" + tx.getFeeTypeId();
            if (!expectedByObligation.containsKey(key)) {
                continue;
            }
            paidByObligation.merge(key, tx.getAmountPaid(), BigDecimal::add);
            if (tx.getMode() == FeeMode.GATEWAY) {
                gateway = gateway.add(tx.getAmountPaid());
            } else {
                manual = manual.add(tx.getAmountPaid());
            }
        }

        return build(expectedByObligation, paidByObligation, manual, gateway);
    }

    /** Shared tallying, so the two cards can never disagree about what "paid" means. */
    private FeeSummaryResponse.CategorySummary build(Map<String, BigDecimal> expected,
                                                     Map<String, BigDecimal> paid,
                                                     BigDecimal manual, BigDecimal gateway) {
        BigDecimal totalExpected = BigDecimal.ZERO;
        BigDecimal totalPaid = BigDecimal.ZERO;
        int paidCount = 0;

        for (Map.Entry<String, BigDecimal> entry : expected.entrySet()) {
            BigDecimal due = entry.getValue();
            BigDecimal got = paid.getOrDefault(entry.getKey(), BigDecimal.ZERO);
            totalExpected = totalExpected.add(due);
            totalPaid = totalPaid.add(got);
            if (due.compareTo(BigDecimal.ZERO) > 0 && got.compareTo(due) >= 0) {
                paidCount++;
            }
        }

        BigDecimal pending = totalExpected.subtract(totalPaid);
        return new FeeSummaryResponse.CategorySummary(
                paidCount, expected.size(), totalExpected, totalPaid, manual, gateway,
                // Floored: an overpaid batch must not show a negative amount still to collect.
                pending.compareTo(BigDecimal.ZERO) < 0 ? BigDecimal.ZERO : pending);
    }

    /**
     * Students of this academy whose name contains the query.
     *
     * <p>One row per person. The prototype searches every course/batch bucket and dedupes by name,
     * because the same student appearing twice reads as two different people.</p>
     */
    @Transactional(readOnly = true)
    public List<StudentSearchResult> searchStudents(String query, int limit) {
        UUID academyId = TenantContext.currentAcademyId();
        String needle = query == null ? "" : query.trim().toLowerCase();
        if (needle.isEmpty()) {
            return List.of();
        }

        List<AcademyMembership> students = membershipRepository.findByAcademyId(academyId).stream()
                .filter(m -> m.getRoleType() == Role.STUDENT && m.getStatus() == MembershipStatus.ACTIVE)
                .toList();
        if (students.isEmpty()) {
            return List.of();
        }

        Map<UUID, User> usersById = userRepository.findAllById(
                students.stream().map(AcademyMembership::getUserId).collect(Collectors.toSet())
        ).stream().collect(Collectors.toMap(User::getId, u -> u));

        List<AcademyMembership> matches = students.stream()
                .filter(m -> {
                    User user = usersById.get(m.getUserId());
                    return user != null && user.getFullName() != null
                            && user.getFullName().toLowerCase().contains(needle);
                })
                .limit(limit)
                .toList();
        if (matches.isEmpty()) {
            return List.of();
        }

        // Which courses each match is enrolled in, so the row can say more than a bare name.
        Map<UUID, String> courseNames = courseRepository.findByAcademyId(academyId).stream()
                .collect(Collectors.toMap(Course::getId, Course::getName));
        Map<UUID, List<String>> coursesByMembership = new HashMap<>();
        for (AcademyMembership membership : matches) {
            List<String> names = courseMapRepository.findByMembershipId(membership.getId()).stream()
                    .filter(CourseMap::isActive)
                    .map(cm -> courseNames.get(cm.getCourseId()))
                    .filter(java.util.Objects::nonNull)
                    .toList();
            coursesByMembership.put(membership.getId(), names);
        }

        List<StudentSearchResult> results = new ArrayList<>();
        Set<UUID> seen = new HashSet<>();
        for (AcademyMembership membership : matches) {
            if (!seen.add(membership.getId())) {
                continue;
            }
            User user = usersById.get(membership.getUserId());
            List<String> names = coursesByMembership.getOrDefault(membership.getId(), List.of());
            results.add(new StudentSearchResult(
                    membership.getId(),
                    user == null ? "Unknown" : user.getFullName(),
                    names.isEmpty() ? "No active courses" : String.join(" · ", names)));
        }
        results.sort(Comparator.comparing(StudentSearchResult::studentName, String.CASE_INSENSITIVE_ORDER));
        return results;
    }
}
