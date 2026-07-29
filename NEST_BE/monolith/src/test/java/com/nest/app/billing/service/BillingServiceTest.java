package com.nest.app.billing.service;

import com.nest.app.academy.entity.Academy;
import com.nest.app.academy.entity.AcademyStatus;
import com.nest.app.academy.repository.AcademyRepository;
import com.nest.app.billing.entity.AcademyInvoice;
import com.nest.app.billing.entity.BillingPlan;
import com.nest.app.billing.entity.InvoiceStatus;
import com.nest.app.billing.repository.AcademyInvoiceRepository;
import com.nest.app.billing.repository.BillingPlanRepository;
import com.nest.common.exception.BadRequestException;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.mockito.junit.jupiter.MockitoSettings;
import org.mockito.quality.Strictness;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * Focused on the properties that actually cost money if they break: not double-charging, not
 * charging suspended or free tenants, and not silently re-pricing an invoice already issued.
 */
@ExtendWith(MockitoExtension.class)
@MockitoSettings(strictness = Strictness.LENIENT)
class BillingServiceTest {

    @Mock
    private AcademyRepository academyRepository;
    @Mock
    private AcademyInvoiceRepository invoiceRepository;
    @Mock
    private BillingPlanRepository planRepository;

    private BillingService service;

    private final UUID academyId = UUID.randomUUID();
    private static final String PERIOD = "2026-07";

    @BeforeEach
    void setUp() {
        service = new BillingService(academyRepository, invoiceRepository, planRepository);
        when(planRepository.findAll()).thenReturn(List.of(
                plan("STANDARD", "2999.00"),
                plan("FREE", "0.00")));
    }

    private BillingPlan plan(String code, String price) {
        return BillingPlan.builder().code(code).displayName(code).monthlyPrice(new BigDecimal(price)).active(true).build();
    }

    private Academy academy(String planCode, AcademyStatus status) {
        return Academy.builder().id(academyId).name("Test Academy").plan(planCode).status(status).build();
    }

    @Test
    void generatesOneInvoiceForAnActivePaidAcademy() {
        when(academyRepository.findAll()).thenReturn(List.of(academy("STANDARD", AcademyStatus.ACTIVE)));
        when(invoiceRepository.findByAcademyIdAndPeriod(academyId, PERIOD)).thenReturn(Optional.empty());

        assertThat(service.generateInvoices(PERIOD)).isEqualTo(1);
        verify(invoiceRepository).save(any(AcademyInvoice.class));
    }

    @Test
    void rerunningTheSamePeriodDoesNotChargeTwice() {
        when(academyRepository.findAll()).thenReturn(List.of(academy("STANDARD", AcademyStatus.ACTIVE)));
        when(invoiceRepository.findByAcademyIdAndPeriod(academyId, PERIOD))
                .thenReturn(Optional.of(AcademyInvoice.builder().id(UUID.randomUUID()).build()));

        assertThat(service.generateInvoices(PERIOD)).isZero();
        verify(invoiceRepository, never()).save(any());
    }

    @Test
    void suspendedAcademiesAreNotInvoiced() {
        when(academyRepository.findAll()).thenReturn(List.of(academy("STANDARD", AcademyStatus.SUSPENDED)));

        assertThat(service.generateInvoices(PERIOD)).isZero();
        verify(invoiceRepository, never()).save(any());
    }

    @Test
    void freePlanGetsNoInvoiceRatherThanAZeroOne() {
        when(academyRepository.findAll()).thenReturn(List.of(academy("FREE", AcademyStatus.ACTIVE)));
        when(invoiceRepository.findByAcademyIdAndPeriod(academyId, PERIOD)).thenReturn(Optional.empty());

        assertThat(service.generateInvoices(PERIOD)).isZero();
        verify(invoiceRepository, never()).save(any());
    }

    @Test
    void unknownPlanIsSkippedRatherThanCrashingTheWholeRun() {
        when(academyRepository.findAll()).thenReturn(List.of(academy("LEGACY_GOLD", AcademyStatus.ACTIVE)));
        when(invoiceRepository.findByAcademyIdAndPeriod(academyId, PERIOD)).thenReturn(Optional.empty());

        assertThat(service.generateInvoices(PERIOD)).isZero();
        verify(invoiceRepository, never()).save(any());
    }

    @Test
    void malformedPeriodIsRejected() {
        assertThatThrownBy(() -> service.generateInvoices("July 2026"))
                .isInstanceOf(BadRequestException.class);
    }

    @Test
    void anAlreadyPaidInvoiceCannotBePaidAgain() {
        UUID invoiceId = UUID.randomUUID();
        when(invoiceRepository.findById(invoiceId)).thenReturn(Optional.of(
                AcademyInvoice.builder().id(invoiceId).status(InvoiceStatus.PAID).build()));

        assertThatThrownBy(() -> service.markPaid(invoiceId,
                new com.nest.app.billing.dto.BillingDtos.MarkPaidRequest(BigDecimal.TEN, "UPI", null, null)))
                .isInstanceOf(BadRequestException.class);
    }

    @Test
    void aPaidInvoiceCannotBeWaived() {
        UUID invoiceId = UUID.randomUUID();
        when(invoiceRepository.findById(invoiceId)).thenReturn(Optional.of(
                AcademyInvoice.builder().id(invoiceId).status(InvoiceStatus.PAID).build()));

        assertThatThrownBy(() -> service.waive(invoiceId, "goodwill"))
                .isInstanceOf(BadRequestException.class);
    }

    @Test
    void overdueIsDerivedFromTheDueDateNotStored() {
        AcademyInvoice due = AcademyInvoice.builder()
                .status(InvoiceStatus.DUE).dueOn(LocalDate.of(2026, 7, 15)).build();

        assertThat(due.isOverdue(LocalDate.of(2026, 7, 14))).isFalse();
        assertThat(due.isOverdue(LocalDate.of(2026, 7, 16))).isTrue();

        due.setStatus(InvoiceStatus.PAID);
        assertThat(due.isOverdue(LocalDate.of(2026, 7, 16))).as("paid is never overdue").isFalse();
    }

    @Test
    void mrrCountsOnlyActivePayingAcademies() {
        Academy paying = academy("STANDARD", AcademyStatus.ACTIVE);
        Academy freeOne = Academy.builder().id(UUID.randomUUID()).name("Free").plan("FREE").status(AcademyStatus.ACTIVE).build();
        Academy suspended = Academy.builder().id(UUID.randomUUID()).name("Susp").plan("STANDARD").status(AcademyStatus.SUSPENDED).build();
        when(academyRepository.findAll()).thenReturn(List.of(paying, freeOne, suspended));
        when(invoiceRepository.sumBilledForPeriod(any())).thenReturn(BigDecimal.ZERO);
        when(invoiceRepository.sumCollectedForPeriod(any())).thenReturn(BigDecimal.ZERO);
        when(invoiceRepository.sumOverdue(any())).thenReturn(BigDecimal.ZERO);
        when(invoiceRepository.findOverdue(any())).thenReturn(List.of());

        var summary = service.summary();

        assertThat(summary.mrr()).isEqualByComparingTo("2999.00");
        assertThat(summary.payingAcademies()).isEqualTo(1);
        assertThat(summary.freeAcademies()).isEqualTo(1);
    }
}
