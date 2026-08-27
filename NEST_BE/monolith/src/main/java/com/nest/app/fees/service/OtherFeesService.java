package com.nest.app.fees.service;

import com.nest.app.curriculum.entity.Course;
import com.nest.app.curriculum.repository.CourseRepository;
import com.nest.app.enrolment.entity.Batch;
import com.nest.app.enrolment.entity.BatchMember;
import com.nest.app.enrolment.repository.BatchMemberRepository;
import com.nest.app.enrolment.repository.BatchRepository;
import com.nest.app.fees.dto.CreateFeeTypeRequest;
import com.nest.app.fees.dto.CreateStudentFeeRequest;
import com.nest.app.fees.dto.FeeRosterResponse;
import com.nest.app.fees.dto.FeeTypeResponse;
import com.nest.app.fees.dto.PaymentStatus;
import com.nest.app.fees.dto.RecordOtherFeeRequest;
import com.nest.app.fees.entity.FeeCategory;
import com.nest.app.fees.entity.FeeType;
import com.nest.app.fees.entity.FeeTypeBatch;
import com.nest.app.fees.entity.FeeTransaction;
import com.nest.app.fees.entity.StudentFee;
import com.nest.app.fees.repository.FeeTransactionRepository;
import com.nest.app.fees.repository.FeeTypeBatchRepository;
import com.nest.app.fees.repository.FeeTypeRepository;
import com.nest.app.fees.repository.StudentFeeRepository;
import com.nest.app.identity.entity.AcademyMembership;
import com.nest.app.identity.entity.MembershipStatus;
import com.nest.app.identity.entity.User;
import com.nest.app.identity.repository.AcademyMembershipRepository;
import com.nest.app.identity.repository.UserRepository;
import com.nest.common.audit.Auditable;
import com.nest.common.exception.ConflictException;
import com.nest.common.exception.ResourceNotFoundException;
import com.nest.common.security.Role;
import com.nest.common.security.TenantContext;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;

/**
 * The "Other Fees" half of the module: costume, exam and annual-day charges raised against
 * batches, plus one-off charges raised against a single student.
 *
 * <p>Separate from {@link FeesService} because the two halves share only the ledger. A regular fee
 * is keyed by course and billing period and generated on a cycle; an Other fee is a one-time
 * charge with a due date and no period at all.</p>
 */
@Service
public class OtherFeesService {

    private final FeeTypeRepository feeTypeRepository;
    private final FeeTypeBatchRepository feeTypeBatchRepository;
    private final StudentFeeRepository studentFeeRepository;
    private final FeeTransactionRepository feeTransactionRepository;
    private final BatchRepository batchRepository;
    private final BatchMemberRepository batchMemberRepository;
    private final CourseRepository courseRepository;
    private final AcademyMembershipRepository membershipRepository;
    private final UserRepository userRepository;

    public OtherFeesService(FeeTypeRepository feeTypeRepository,
                            FeeTypeBatchRepository feeTypeBatchRepository,
                            StudentFeeRepository studentFeeRepository,
                            FeeTransactionRepository feeTransactionRepository,
                            BatchRepository batchRepository,
                            BatchMemberRepository batchMemberRepository,
                            CourseRepository courseRepository,
                            AcademyMembershipRepository membershipRepository,
                            UserRepository userRepository) {
        this.feeTypeRepository = feeTypeRepository;
        this.feeTypeBatchRepository = feeTypeBatchRepository;
        this.studentFeeRepository = studentFeeRepository;
        this.feeTransactionRepository = feeTransactionRepository;
        this.batchRepository = batchRepository;
        this.batchMemberRepository = batchMemberRepository;
        this.courseRepository = courseRepository;
        this.membershipRepository = membershipRepository;
        this.userRepository = userRepository;
    }

    @Transactional(readOnly = true)
    public List<FeeTypeResponse> listFeeTypes(boolean includeRetired) {
        UUID academyId = TenantContext.currentAcademyId();
        List<FeeType> types = includeRetired
                ? feeTypeRepository.findByAcademyIdOrderByNameAsc(academyId)
                : feeTypeRepository.findByAcademyIdAndActiveTrueOrderByNameAsc(academyId);
        if (types.isEmpty()) {
            return List.of();
        }

        Map<UUID, List<FeeTypeBatch>> bindingsByType = feeTypeBatchRepository
                .findByFeeTypeIdIn(types.stream().map(FeeType::getId).toList()).stream()
                .collect(Collectors.groupingBy(FeeTypeBatch::getFeeTypeId));

        Set<UUID> batchIds = bindingsByType.values().stream().flatMap(List::stream)
                .map(FeeTypeBatch::getBatchId).collect(Collectors.toSet());
        Map<UUID, Batch> batchesById = batchRepository.findAllById(batchIds).stream()
                .collect(Collectors.toMap(Batch::getId, b -> b));
        Map<UUID, String> courseNames = courseRepository.findAllById(
                batchesById.values().stream().map(Batch::getCourseId).collect(Collectors.toSet())
        ).stream().collect(Collectors.toMap(Course::getId, Course::getName));

        return types.stream().map(type -> toResponse(type, bindingsByType.getOrDefault(type.getId(), List.of()),
                batchesById, courseNames)).toList();
    }

    @Transactional
    @Auditable(action = "FEE_TYPE_CREATED", entityType = "fee_type")
    public FeeTypeResponse createFeeType(CreateFeeTypeRequest request) {
        UUID academyId = TenantContext.currentAcademyId();
        String name = request.name().trim();

        // Checked here for a clear message; the (academy_id, name) unique index is what actually
        // guarantees it under two concurrent creates.
        if (feeTypeRepository.existsByAcademyIdAndNameIgnoreCase(academyId, name)) {
            throw new ConflictException("A fee type called \"" + name + "\" already exists.");
        }

        // Batches are client-supplied ids. Without this check one academy could bind its fee type
        // to another's batch and start charging their students.
        List<Batch> batches = batchRepository.findAllById(request.batchIds());
        assertBatchesBelongToAcademy(batches, request.batchIds(), academyId);

        FeeType type = feeTypeRepository.save(FeeType.builder()
                .academyId(academyId)
                .name(name)
                .amount(request.amount())
                .dueDate(request.dueDate())
                .defaultMode(request.defaultMode())
                .active(true)
                .createdBy(TenantContext.currentUserId())
                .build());

        for (UUID batchId : request.batchIds().stream().distinct().toList()) {
            feeTypeBatchRepository.save(FeeTypeBatch.builder()
                    .feeTypeId(type.getId()).batchId(batchId).build());
        }

        return listFeeTypes(false).stream()
                .filter(t -> t.id().equals(type.getId()))
                .findFirst()
                .orElseThrow(() -> new IllegalStateException("Fee type vanished after creation"));
    }

    @Transactional
    @Auditable(action = "STUDENT_FEE_CREATED", entityType = "student_fee")
    public UUID createStudentFee(CreateStudentFeeRequest request) {
        UUID academyId = TenantContext.currentAcademyId();
        AcademyMembership membership = membershipRepository.findById(request.membershipId())
                .orElseThrow(() -> new ResourceNotFoundException("Student not found: " + request.membershipId()));
        if (!membership.getAcademyId().equals(academyId)) {
            throw new ResourceNotFoundException("Student not found: " + request.membershipId());
        }

        StudentFee fee = studentFeeRepository.save(StudentFee.builder()
                .academyId(academyId)
                .membershipId(request.membershipId())
                .name(request.name().trim())
                .amount(request.amount())
                .dueDate(request.dueDate())
                .defaultMode(request.defaultMode())
                .note(request.note())
                .createdBy(TenantContext.currentUserId())
                .build());
        return fee.getId();
    }

    /**
     * Everyone in a batch and where they stand on one fee type.
     *
     * <p>Unlike a regular fee, the amount is the same for every student - a costume costs what it
     * costs - so there is no per-student agreed figure to look up.</p>
     */
    @Transactional(readOnly = true)
    public FeeRosterResponse roster(UUID feeTypeId, UUID batchId) {
        UUID academyId = TenantContext.currentAcademyId();
        FeeType type = feeTypeRepository.findByIdAndAcademyId(feeTypeId, academyId)
                .orElseThrow(() -> new ResourceNotFoundException("Fee type not found: " + feeTypeId));

        Batch batch = batchRepository.findById(batchId)
                .orElseThrow(() -> new ResourceNotFoundException("Batch not found: " + batchId));
        assertBatchesBelongToAcademy(List.of(batch), List.of(batchId), academyId);

        // The fee only applies to batches it is bound to. Showing a roster for an unbound batch
        // would invite collecting a charge those students were never billed.
        boolean bound = feeTypeBatchRepository.findByFeeTypeId(feeTypeId).stream()
                .anyMatch(b -> b.getBatchId().equals(batchId));
        if (!bound) {
            throw new ConflictException("\"" + type.getName() + "\" does not apply to this batch.");
        }

        List<UUID> memberIds = batchMemberRepository.findByBatchId(batchId).stream()
                .map(BatchMember::getMembershipId).toList();
        if (memberIds.isEmpty()) {
            return new FeeRosterResponse(batch.getCourseId(), batchId, type.getName(),
                    0, 0, BigDecimal.ZERO, BigDecimal.ZERO, List.of());
        }

        List<AcademyMembership> students = membershipRepository.findAllById(memberIds).stream()
                .filter(m -> m.getRoleType() == Role.STUDENT && m.getStatus() == MembershipStatus.ACTIVE)
                .filter(m -> m.getAcademyId().equals(academyId))
                .toList();
        Map<UUID, User> usersById = userRepository.findAllById(
                students.stream().map(AcademyMembership::getUserId).collect(Collectors.toSet())
        ).stream().collect(Collectors.toMap(User::getId, u -> u));

        List<FeeTransaction> transactions = feeTransactionRepository.findByFeeTypeId(feeTypeId);
        Map<UUID, List<FeeTransaction>> txByMembership = transactions.stream()
                .collect(Collectors.groupingBy(FeeTransaction::getMembershipId));
        Set<UUID> reversedIds = transactions.stream()
                .map(FeeTransaction::getReversalOfTransactionId)
                .filter(Objects::nonNull)
                .collect(Collectors.toSet());

        LocalDate today = LocalDate.now();
        BigDecimal amount = type.getAmount();
        List<FeeRosterResponse.FeeRosterEntry> entries = new ArrayList<>();
        int paidCount = 0;

        for (AcademyMembership membership : students) {
            List<FeeTransaction> rows = txByMembership.getOrDefault(membership.getId(), List.of());
            BigDecimal paid = rows.stream().map(FeeTransaction::getAmountPaid)
                    .reduce(BigDecimal.ZERO, BigDecimal::add);
            BigDecimal balance = amount.subtract(paid);

            FeeTransaction lastPayment = rows.stream()
                    .filter(t -> !t.isReversal())
                    .filter(t -> !reversedIds.contains(t.getId()))
                    .max(Comparator.comparing(FeeTransaction::getCreatedAt,
                            Comparator.nullsFirst(Comparator.naturalOrder())))
                    .orElse(null);

            PaymentStatus status = deriveStatus(amount, paid, balance, lastPayment,
                    type.getDueDate(), today);
            if (status.isSettled()) {
                paidCount++;
            }

            User user = usersById.get(membership.getUserId());
            entries.add(new FeeRosterResponse.FeeRosterEntry(
                    membership.getId(),
                    user == null ? "Unknown" : user.getFullName(),
                    amount, paid, balance, status,
                    lastPayment == null ? null : lastPayment.getId(),
                    lastPayment == null ? null : lastPayment.getOccurredOn(),
                    lastPayment == null ? null : lastPayment.getMode()));
        }

        entries.sort(Comparator.comparing(FeeRosterResponse.FeeRosterEntry::studentName,
                String.CASE_INSENSITIVE_ORDER));

        return new FeeRosterResponse(batch.getCourseId(), batchId, type.getName(),
                entries.size(), paidCount,
                amount.multiply(BigDecimal.valueOf(entries.size())),
                entries.stream().map(FeeRosterResponse.FeeRosterEntry::totalPaid)
                        .reduce(BigDecimal.ZERO, BigDecimal::add),
                entries);
    }

    @Transactional
    @Auditable(action = "OTHER_FEE_RECORDED", entityType = "fee_transaction")
    public UUID recordPayment(RecordOtherFeeRequest request) {
        UUID academyId = TenantContext.currentAcademyId();

        boolean hasType = request.feeTypeId() != null;
        boolean hasStudentFee = request.studentFeeId() != null;
        // Rejected here rather than left to the database's check constraint, so the caller gets a
        // sentence instead of a constraint name.
        if (hasType == hasStudentFee) {
            throw new ConflictException(
                    "A payment must be against exactly one of a fee type or a student fee.");
        }

        // Both lookups are by id AND academy: these ids come from a client and must not resolve
        // outside the caller's own tenant.
        if (hasType) {
            feeTypeRepository.findByIdAndAcademyId(request.feeTypeId(), academyId)
                    .orElseThrow(() -> new ResourceNotFoundException("Fee type not found"));
        } else {
            StudentFee fee = studentFeeRepository.findByIdAndAcademyId(request.studentFeeId(), academyId)
                    .orElseThrow(() -> new ResourceNotFoundException("Student fee not found"));
            if (!fee.getMembershipId().equals(request.membershipId())) {
                throw new ConflictException("That fee belongs to a different student.");
            }
        }

        FeeTransaction tx = feeTransactionRepository.saveAndFlush(FeeTransaction.builder()
                .academyId(academyId)
                .category(FeeCategory.OTHER)
                .membershipId(request.membershipId())
                // Deliberately null for an Other fee - it has no course and no billing period, and
                // the database's category check enforces that.
                .courseId(null)
                .period(null)
                .feeTypeId(request.feeTypeId())
                .studentFeeId(request.studentFeeId())
                .amountPaid(request.amountPaid())
                .mode(request.mode())
                .gatewayRef(request.gatewayRef())
                .note(request.note())
                .recordedBy(TenantContext.currentUserId())
                .occurredOn(request.receivedOn() != null ? request.receivedOn() : LocalDate.now())
                .build());
        return tx.getId();
    }

    /**
     * Every payment the academy took in a date range, across both categories.
     *
     * <p>Lives here rather than in {@link FeesService} because it spans both halves and neither
     * owns it. Reversals are included: the totals are net, so omitting them would make the figures
     * impossible to reconcile against the rows.</p>
     */
    @Transactional(readOnly = true)
    public com.nest.app.fees.dto.TransactionLedgerResponse ledger(
            LocalDate from, LocalDate to, FeeCategory category, String query) {
        UUID academyId = TenantContext.currentAcademyId();
        List<FeeTransaction> transactions = feeTransactionRepository
                .findByAcademyIdAndOccurredOnBetweenOrderByOccurredOnDesc(academyId, from, to);
        if (transactions.isEmpty()) {
            return new com.nest.app.fees.dto.TransactionLedgerResponse(
                    BigDecimal.ZERO, BigDecimal.ZERO, BigDecimal.ZERO, List.of());
        }

        Map<UUID, String> studentNames = resolveStudentNames(transactions.stream()
                .map(FeeTransaction::getMembershipId).collect(Collectors.toSet()));

        Map<UUID, String> courseNames = courseRepository.findAllById(transactions.stream()
                        .map(FeeTransaction::getCourseId).filter(Objects::nonNull)
                        .collect(Collectors.toSet())).stream()
                .collect(Collectors.toMap(Course::getId, Course::getName));

        Map<UUID, String> feeTypeNames = feeTypeRepository.findAllById(transactions.stream()
                        .map(FeeTransaction::getFeeTypeId).filter(Objects::nonNull)
                        .collect(Collectors.toSet())).stream()
                .collect(Collectors.toMap(FeeType::getId, FeeType::getName));

        Map<UUID, String> studentFeeNames = studentFeeRepository.findAllById(transactions.stream()
                        .map(FeeTransaction::getStudentFeeId).filter(Objects::nonNull)
                        .collect(Collectors.toSet())).stream()
                .collect(Collectors.toMap(StudentFee::getId, StudentFee::getName));

        String needle = query == null ? null : query.trim().toLowerCase();
        List<com.nest.app.fees.dto.TransactionLedgerResponse.LedgerEntry> entries = new ArrayList<>();
        BigDecimal regularTotal = BigDecimal.ZERO;
        BigDecimal otherTotal = BigDecimal.ZERO;

        for (FeeTransaction tx : transactions) {
            if (category != null && tx.getCategory() != category) {
                continue;
            }
            String name = studentNames.getOrDefault(tx.getMembershipId(), "Unknown");
            if (needle != null && !needle.isEmpty() && !name.toLowerCase().contains(needle)) {
                continue;
            }

            String context = switch (tx.getCategory()) {
                case REGULAR -> courseNames.getOrDefault(tx.getCourseId(), "Unknown course")
                        + (tx.getPeriod() == null ? "" : " · " + tx.getPeriod());
                case OTHER -> tx.getFeeTypeId() != null
                        ? feeTypeNames.getOrDefault(tx.getFeeTypeId(), "Fee")
                        : studentFeeNames.getOrDefault(tx.getStudentFeeId(), "Individual fee");
            };

            entries.add(new com.nest.app.fees.dto.TransactionLedgerResponse.LedgerEntry(
                    tx.getId(), tx.getMembershipId(), name, tx.getCategory(), context,
                    tx.getAmountPaid(), tx.getMode(), tx.getOccurredOn(), tx.isReversal()));

            // Totals follow the same filters as the rows, so the tiles always explain the list.
            if (tx.getCategory() == FeeCategory.REGULAR) {
                regularTotal = regularTotal.add(tx.getAmountPaid());
            } else {
                otherTotal = otherTotal.add(tx.getAmountPaid());
            }
        }

        return new com.nest.app.fees.dto.TransactionLedgerResponse(
                regularTotal, otherTotal, regularTotal.add(otherTotal), entries);
    }

    private Map<UUID, String> resolveStudentNames(Set<UUID> membershipIds) {
        List<AcademyMembership> memberships = membershipRepository.findAllById(membershipIds);
        Map<UUID, User> usersById = userRepository.findAllById(
                memberships.stream().map(AcademyMembership::getUserId).collect(Collectors.toSet())
        ).stream().collect(Collectors.toMap(User::getId, u -> u));
        return memberships.stream().collect(Collectors.toMap(
                AcademyMembership::getId,
                m -> {
                    User user = usersById.get(m.getUserId());
                    return user == null ? "Unknown" : user.getFullName();
                }));
    }

    /**
     * Status for an Other fee. Simpler than the regular one: there is no billing period and no
     * closing, so "due" is driven by the fee type's own last date to pay.
     */
    private PaymentStatus deriveStatus(BigDecimal amount, BigDecimal paid, BigDecimal balance,
                                       FeeTransaction lastPayment, LocalDate dueDate, LocalDate today) {
        if (balance.compareTo(BigDecimal.ZERO) <= 0 && amount.compareTo(BigDecimal.ZERO) > 0) {
            return lastPayment != null && lastPayment.getMode() == com.nest.app.fees.entity.FeeMode.GATEWAY
                    ? PaymentStatus.PAID_GATEWAY
                    : PaymentStatus.PAID_MANUAL;
        }
        if (paid.compareTo(BigDecimal.ZERO) > 0) {
            return PaymentStatus.PARTIAL;
        }
        return dueDate != null && dueDate.isBefore(today) ? PaymentStatus.DUE : PaymentStatus.NOT_PAID;
    }

    private void assertBatchesBelongToAcademy(List<Batch> batches, List<UUID> requestedIds, UUID academyId) {
        if (batches.size() != requestedIds.stream().distinct().count()) {
            throw new ResourceNotFoundException("One or more batches do not exist");
        }
        Set<UUID> courseIds = batches.stream().map(Batch::getCourseId).collect(Collectors.toSet());
        List<Course> courses = courseRepository.findAllById(courseIds);
        if (courses.size() != courseIds.size()
                || courses.stream().anyMatch(c -> !academyId.equals(c.getAcademyId()))) {
            throw new ResourceNotFoundException("One or more batches do not exist");
        }
    }

    private FeeTypeResponse toResponse(FeeType type, List<FeeTypeBatch> bindings,
                                       Map<UUID, Batch> batchesById, Map<UUID, String> courseNames) {
        List<FeeTypeResponse.BatchBinding> batches = bindings.stream()
                .map(b -> batchesById.get(b.getBatchId()))
                .filter(Objects::nonNull)
                .map(b -> new FeeTypeResponse.BatchBinding(
                        b.getId(), b.getName(), b.getCourseId(),
                        courseNames.getOrDefault(b.getCourseId(), "Unknown course")))
                .sorted(Comparator.comparing(FeeTypeResponse.BatchBinding::courseName,
                        String.CASE_INSENSITIVE_ORDER))
                .toList();
        return new FeeTypeResponse(type.getId(), type.getName(), type.getAmount(), type.getDueDate(),
                type.getDefaultMode(), type.isActive(), batches);
    }
}
