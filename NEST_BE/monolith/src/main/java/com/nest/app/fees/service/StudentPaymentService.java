package com.nest.app.fees.service;

import com.nest.app.fees.dto.PayFeeRequest;
import com.nest.app.fees.dto.PayFeeResponse;
import com.nest.app.fees.dto.StudentOtherFeesResponse;
import com.nest.app.fees.dto.StudentStatementResponse;
import com.nest.app.fees.entity.FeeCategory;
import com.nest.app.fees.entity.FeeMode;
import com.nest.app.fees.entity.FeeTransaction;
import com.nest.app.fees.repository.FeeTransactionRepository;
import com.nest.common.audit.Auditable;
import com.nest.common.exception.ConflictException;
import com.nest.common.exception.ResourceNotFoundException;
import com.nest.common.security.TenantContext;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.UUID;

/**
 * A student paying their OWN fee online.
 *
 * <p>There is no real payment provider behind this yet. What exists is the whole flow around one:
 * the amount is always computed here from the ledger (never taken from the client), the payment is
 * recorded as a GATEWAY transaction against exactly the row being paid, and the reference is
 * stored. Swapping in a real provider means replacing {@link #charge} - and nothing else.</p>
 *
 * <p>Because the placeholder "charge" always succeeds, it is OFF unless
 * {@code nest.payments.mock-enabled=true}. With it off, no endpoint here marks anything paid, so a
 * production deployment cannot have fees settled by a button that moves no money.</p>
 */
@Service
public class StudentPaymentService {

    private final FeesService feesService;
    private final OtherFeesService otherFeesService;
    private final FeeTransactionRepository transactionRepository;
    private final boolean mockEnabled;

    public StudentPaymentService(FeesService feesService, OtherFeesService otherFeesService,
                                 FeeTransactionRepository transactionRepository,
                                 @Value("${nest.payments.mock-enabled:false}") boolean mockEnabled) {
        this.feesService = feesService;
        this.otherFeesService = otherFeesService;
        this.transactionRepository = transactionRepository;
        this.mockEnabled = mockEnabled;
    }

    public boolean enabled() {
        return mockEnabled;
    }

    @Transactional
    @Auditable(action = "STUDENT_FEE_PAID_ONLINE", entityType = "fee_transaction")
    public PayFeeResponse pay(PayFeeRequest request) {
        if (!mockEnabled) {
            throw new ConflictException("Online payments are not enabled for this academy yet.");
        }
        Due due = resolveDue(request);

        String gatewayRef = charge(due.amount());
        FeeTransaction saved = transactionRepository.saveAndFlush(
                due.toTransaction(TenantContext.currentAcademyId(), TenantContext.currentMembershipId(),
                        TenantContext.currentUserId())
                        .amountPaid(due.amount()).gatewayRef(gatewayRef)
                        .note("Paid online (" + request.method() + ")").build());
        return new PayFeeResponse(saved.getId(), due.amount(), gatewayRef);
    }

    /**
     * What the caller owes on the fee they named, worked out from the ledger. Shared by the mock
     * charge and the real gateway so both price a payment the same way - and neither can be talked
     * into a different amount by the client.
     */
    public Due resolveDue(PayFeeRequest request) {
        UUID me = TenantContext.currentMembershipId();
        BigDecimal outstanding;
        if (request.category() == FeeCategory.REGULAR) {
            if (request.courseId() == null || request.period() == null) {
                throw new ConflictException("A course fee payment needs the course and period.");
            }
            StudentStatementResponse.StatementRow row = feesService.statement(me, FeeCategory.REGULAR).rows().stream()
                    .filter(r -> request.courseId().equals(r.courseId()) && request.period().equals(r.label()))
                    .findFirst().orElseThrow(() -> new ResourceNotFoundException("Fee not found"));
            outstanding = row.fee().subtract(row.paid());
        } else {
            if ((request.feeTypeId() == null) == (request.studentFeeId() == null)) {
                throw new ConflictException("A payment must be against exactly one fee.");
            }
            StudentOtherFeesResponse.OtherFeeRow row = otherFeesService.studentOtherFees(me).fees().stream()
                    .filter(r -> request.feeTypeId() != null
                            ? request.feeTypeId().equals(r.feeTypeId())
                            : request.studentFeeId().equals(r.studentFeeId()))
                    .findFirst().orElseThrow(() -> new ResourceNotFoundException("Fee not found"));
            outstanding = row.balance();
        }

        if (outstanding.signum() <= 0) {
            throw new ConflictException("Nothing is owed on this fee.");
        }
        return request.category() == FeeCategory.REGULAR
                ? new Due(FeeCategory.REGULAR, request.courseId(), request.period(), null, null, outstanding)
                : new Due(FeeCategory.OTHER, null, null, request.feeTypeId(), request.studentFeeId(), outstanding);
    }

    /** One fee being paid and the amount still owed on it. */
    public record Due(FeeCategory category, UUID courseId, String period, UUID feeTypeId, UUID studentFeeId,
                      BigDecimal amount) {

        /** A GATEWAY ledger row against exactly this fee, ready for the amount and reference. */
        public FeeTransaction.FeeTransactionBuilder toTransaction(UUID academyId, UUID membershipId, UUID recordedBy) {
            return FeeTransaction.builder()
                    .academyId(academyId)
                    .membershipId(membershipId)
                    .mode(FeeMode.GATEWAY)
                    .recordedBy(recordedBy)
                    .occurredOn(LocalDate.now())
                    .category(category)
                    .courseId(courseId)
                    .period(period)
                    .feeTypeId(feeTypeId)
                    .studentFeeId(studentFeeId);
        }
    }

    /** The seam for a real provider: take the money and return its reference. */
    private String charge(BigDecimal amount) {
        return "MOCK-" + UUID.randomUUID().toString().substring(0, 8).toUpperCase();
    }
}
