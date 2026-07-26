package com.nest.app.fees.service;

import com.nest.app.curriculum.repository.CourseRepository;
import com.nest.app.fees.dto.RecordFeeEntryRequest;
import com.nest.app.fees.entity.FeeMode;
import com.nest.app.fees.entity.FeeSlip;
import com.nest.app.fees.entity.FeeSlipStatus;
import com.nest.app.fees.entity.FeeTransaction;
import com.nest.app.fees.repository.FeeSlipRepository;
import com.nest.app.fees.repository.FeeTransactionRepository;
import com.nest.app.identity.entity.CourseMap;
import com.nest.app.identity.repository.AcademyMembershipRepository;
import com.nest.app.identity.repository.CourseMapRepository;
import com.nest.app.identity.repository.UserRepository;
import com.nest.common.exception.ResourceNotFoundException;
import com.nest.common.security.NestPrincipal;
import com.nest.common.security.Role;
import com.nest.common.security.TenantContext;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.math.BigDecimal;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/** Covers PRD 3.9.2: balance = agreed fee - SUM(paid), and partial payments accumulate rather
 * than overwrite. */
@ExtendWith(MockitoExtension.class)
class FeesServiceTest {

    @Mock
    private FeeTransactionRepository feeTransactionRepository;
    @Mock
    private CourseMapRepository courseMapRepository;
    @Mock
    private FeeSlipRepository feeSlipRepository;
    @Mock
    private CourseRepository courseRepository;
    @Mock
    private AcademyMembershipRepository membershipRepository;
    @Mock
    private UserRepository userRepository;
    @Mock
    private com.nest.app.identity.service.CourseFeatureGuard courseFeatureGuard;

    private FeesService feesService;

    private final UUID membershipId = UUID.randomUUID();
    private final UUID courseId = UUID.randomUUID();

    @BeforeEach
    void setUp() {
        feesService = new FeesService(feeTransactionRepository, courseMapRepository, feeSlipRepository,
                courseRepository, membershipRepository, userRepository, courseFeatureGuard);
        TenantContext.set(new NestPrincipal(UUID.randomUUID(), "meera", Role.ACADEMY_ADMIN, List.of(), null));
    }

    @AfterEach
    void tearDown() {
        TenantContext.clear();
    }

    @Test
    void balanceIsAgreedFeeMinusSumOfPayments() {
        CourseMap enrolment = CourseMap.builder().membershipId(membershipId).courseId(courseId)
                .agreedFee(new BigDecimal("1500.00")).build();
        when(courseMapRepository.findByMembershipIdAndCourseId(membershipId, courseId)).thenReturn(Optional.of(enrolment));
        when(feeTransactionRepository.sumPaid(membershipId, courseId, "2026-07")).thenReturn(new BigDecimal("750.00"));

        var balance = feesService.getBalance(membershipId, courseId, "2026-07");

        assertThat(balance.agreedFee()).isEqualByComparingTo("1500.00");
        assertThat(balance.totalPaid()).isEqualByComparingTo("750.00");
        assertThat(balance.balance()).isEqualByComparingTo("750.00");
    }

    @Test
    void fullyPaidPeriodHasZeroBalance() {
        CourseMap enrolment = CourseMap.builder().membershipId(membershipId).courseId(courseId)
                .agreedFee(new BigDecimal("1200.00")).build();
        when(courseMapRepository.findByMembershipIdAndCourseId(membershipId, courseId)).thenReturn(Optional.of(enrolment));
        when(feeTransactionRepository.sumPaid(membershipId, courseId, "2026-07")).thenReturn(new BigDecimal("1200.00"));

        assertThat(feesService.getBalance(membershipId, courseId, "2026-07").balance()).isEqualByComparingTo("0.00");
    }

    @Test
    void missingEnrolmentIsRejected() {
        when(courseMapRepository.findByMembershipIdAndCourseId(membershipId, courseId)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> feesService.getBalance(membershipId, courseId, "2026-07"))
                .isInstanceOf(ResourceNotFoundException.class);
    }

    @Test
    void recordEntryStampsRecordingUserForAudit() {
        UUID adminUserId = UUID.randomUUID();
        TenantContext.set(new NestPrincipal(adminUserId, "meera", Role.ACADEMY_ADMIN, List.of(), null));
        when(feeTransactionRepository.saveAndFlush(any(FeeTransaction.class))).thenAnswer(inv -> {
            FeeTransaction tx = inv.getArgument(0);
            tx.setId(UUID.randomUUID());
            return tx;
        });

        var response = feesService.recordEntry(new RecordFeeEntryRequest(
                membershipId, courseId, "2026-07", new BigDecimal("750.00"), FeeMode.CASH, "Half fee - attendance", null, null));

        assertThat(response.recordedBy()).isEqualTo(adminUserId);
        assertThat(response.amountPaid()).isEqualByComparingTo("750.00");
        verify(feeSlipRepository, never()).save(any(FeeSlip.class));
    }

    @Test
    void closingAPartialPaymentMarksTheExistingSlipClosed() {
        when(feeTransactionRepository.saveAndFlush(any(FeeTransaction.class))).thenAnswer(inv -> {
            FeeTransaction tx = inv.getArgument(0);
            tx.setId(UUID.randomUUID());
            return tx;
        });
        FeeSlip existingSlip = FeeSlip.builder().id(UUID.randomUUID()).membershipId(membershipId).courseId(courseId)
                .period("2026-07").amountDue(new BigDecimal("1000.00")).status(FeeSlipStatus.OPEN).build();
        when(feeSlipRepository.findByMembershipIdAndCourseIdAndPeriod(membershipId, courseId, "2026-07"))
                .thenReturn(Optional.of(existingSlip));
        when(feeSlipRepository.save(any(FeeSlip.class))).thenAnswer(inv -> inv.getArgument(0));

        feesService.recordEntry(new RecordFeeEntryRequest(
                membershipId, courseId, "2026-07", new BigDecimal("500.00"), FeeMode.CASH, "Paying half, writing off the rest", null, true));

        ArgumentCaptor<FeeSlip> captor = ArgumentCaptor.forClass(FeeSlip.class);
        verify(feeSlipRepository).save(captor.capture());
        assertThat(captor.getValue().getStatus()).isEqualTo(FeeSlipStatus.CLOSED);
    }

    @Test
    void closingAPeriodWithNoExistingSlipCreatesOneFromTheAgreedFee() {
        when(feeTransactionRepository.saveAndFlush(any(FeeTransaction.class))).thenAnswer(inv -> {
            FeeTransaction tx = inv.getArgument(0);
            tx.setId(UUID.randomUUID());
            return tx;
        });
        when(feeSlipRepository.findByMembershipIdAndCourseIdAndPeriod(membershipId, courseId, "2026-07")).thenReturn(Optional.empty());
        when(courseMapRepository.findByMembershipIdAndCourseId(membershipId, courseId))
                .thenReturn(Optional.of(CourseMap.builder().membershipId(membershipId).courseId(courseId)
                        .agreedFee(new BigDecimal("1000.00")).build()));
        when(feeSlipRepository.save(any(FeeSlip.class))).thenAnswer(inv -> inv.getArgument(0));

        feesService.recordEntry(new RecordFeeEntryRequest(
                membershipId, courseId, "2026-07", new BigDecimal("500.00"), FeeMode.CASH, null, null, true));

        ArgumentCaptor<FeeSlip> captor = ArgumentCaptor.forClass(FeeSlip.class);
        verify(feeSlipRepository).save(captor.capture());
        assertThat(captor.getValue().getStatus()).isEqualTo(FeeSlipStatus.CLOSED);
        assertThat(captor.getValue().getAmountDue()).isEqualByComparingTo("1000.00");
    }
}
