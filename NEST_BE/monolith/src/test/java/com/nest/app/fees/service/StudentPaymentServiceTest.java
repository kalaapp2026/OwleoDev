package com.nest.app.fees.service;

import com.nest.app.fees.dto.PayFeeRequest;
import com.nest.app.fees.dto.PayFeeResponse;
import com.nest.app.fees.dto.PaymentStatus;
import com.nest.app.fees.dto.StudentOtherFeesResponse;
import com.nest.app.fees.entity.FeeCategory;
import com.nest.app.fees.entity.FeeMode;
import com.nest.app.fees.entity.FeeTransaction;
import com.nest.app.fees.repository.FeeTransactionRepository;
import com.nest.common.exception.ConflictException;
import com.nest.common.security.MembershipClaim;
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
import java.util.Set;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class StudentPaymentServiceTest {

    @Mock FeesService feesService;
    @Mock OtherFeesService otherFeesService;
    @Mock FeeTransactionRepository transactionRepository;

    private final UUID academyId = UUID.randomUUID();
    private final UUID membershipId = UUID.randomUUID();
    private final UUID feeTypeId = UUID.randomUUID();

    @BeforeEach
    void setUp() {
        TenantContext.set(new NestPrincipal(UUID.randomUUID(), "ishaan", Role.STUDENT,
                List.of(new MembershipClaim(membershipId, academyId, "Owleo", Role.STUDENT, Set.of(), Set.of())),
                membershipId));
    }

    @AfterEach
    void tearDown() {
        TenantContext.clear();
    }

    private PayFeeRequest otherFee() {
        return new PayFeeRequest(FeeCategory.OTHER, null, null, feeTypeId, null, "UPI");
    }

    @Test
    void switchedOffItSettlesNothing() {
        var service = new StudentPaymentService(feesService, otherFeesService, transactionRepository, false);

        assertThatThrownBy(() -> service.pay(otherFee())).isInstanceOf(ConflictException.class);
        verify(transactionRepository, never()).saveAndFlush(any());
    }

    @Test
    void theAmountIsWhatTheLedgerSaysIsOwedNeverWhatTheClientSent() {
        var row = new StudentOtherFeesResponse.OtherFeeRow(feeTypeId, null, "Costume",
                new BigDecimal("900"), new BigDecimal("400"), new BigDecimal("500"),
                PaymentStatus.PARTIAL, null, null, null, null, false);
        when(otherFeesService.studentOtherFees(membershipId)).thenReturn(
                new StudentOtherFeesResponse(membershipId, "Ishaan", new BigDecimal("900"),
                        new BigDecimal("400"), new BigDecimal("500"), List.of(row)));
        when(transactionRepository.saveAndFlush(any())).thenAnswer(i -> {
            FeeTransaction t = i.getArgument(0);
            t.setId(UUID.randomUUID());
            return t;
        });
        var service = new StudentPaymentService(feesService, otherFeesService, transactionRepository, true);

        PayFeeResponse response = service.pay(otherFee());

        ArgumentCaptor<FeeTransaction> saved = ArgumentCaptor.forClass(FeeTransaction.class);
        verify(transactionRepository).saveAndFlush(saved.capture());
        assertThat(response.amount()).isEqualByComparingTo("500");
        assertThat(saved.getValue().getAmountPaid()).isEqualByComparingTo("500");
        assertThat(saved.getValue().getMode()).isEqualTo(FeeMode.GATEWAY);
        assertThat(saved.getValue().getMembershipId()).isEqualTo(membershipId);
    }

    @Test
    void aFullyPaidFeeCannotBePaidAgain() {
        var row = new StudentOtherFeesResponse.OtherFeeRow(feeTypeId, null, "Costume",
                new BigDecimal("900"), new BigDecimal("900"), BigDecimal.ZERO,
                PaymentStatus.PAID_MANUAL, null, null, null, null, false);
        when(otherFeesService.studentOtherFees(membershipId)).thenReturn(
                new StudentOtherFeesResponse(membershipId, "Ishaan", new BigDecimal("900"),
                        new BigDecimal("900"), BigDecimal.ZERO, List.of(row)));
        var service = new StudentPaymentService(feesService, otherFeesService, transactionRepository, true);

        assertThatThrownBy(() -> service.pay(otherFee())).isInstanceOf(ConflictException.class);
        verify(transactionRepository, never()).saveAndFlush(any());
    }
}
