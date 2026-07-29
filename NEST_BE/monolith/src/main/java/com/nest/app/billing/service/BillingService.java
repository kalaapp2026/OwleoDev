package com.nest.app.billing.service;

import com.nest.app.academy.entity.Academy;
import com.nest.app.academy.entity.AcademyStatus;
import com.nest.app.academy.repository.AcademyRepository;
import com.nest.app.billing.dto.BillingDtos;
import com.nest.app.billing.entity.AcademyInvoice;
import com.nest.app.billing.entity.BillingPlan;
import com.nest.app.billing.entity.InvoiceStatus;
import com.nest.app.billing.repository.AcademyInvoiceRepository;
import com.nest.app.billing.repository.BillingPlanRepository;
import com.nest.common.audit.Auditable;
import com.nest.common.exception.BadRequestException;
import com.nest.common.exception.ResourceNotFoundException;
import com.nest.common.security.TenantContext;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.time.Instant;
import java.time.LocalDate;
import java.time.YearMonth;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

/**
 * Platform billing (PRD 2.4 addendum): what each academy owes NEST for using the platform. The
 * opposite direction of money from {@code FeesService}, which is an academy billing its students.
 *
 * <p>Payments are recorded by hand today - there's no gateway integration - so every "paid" row
 * carries who entered it. That's deliberate: an operator-entered payment with no attribution is
 * unauditable.
 */
@Service
public class BillingService {

    private static final Logger log = LoggerFactory.getLogger(BillingService.class);

    /** Days after issue before an invoice counts as overdue. */
    private static final int PAYMENT_TERM_DAYS = 14;

    private final AcademyRepository academyRepository;
    private final AcademyInvoiceRepository invoiceRepository;
    private final BillingPlanRepository planRepository;

    public BillingService(AcademyRepository academyRepository, AcademyInvoiceRepository invoiceRepository,
                          BillingPlanRepository planRepository) {
        this.academyRepository = academyRepository;
        this.invoiceRepository = invoiceRepository;
        this.planRepository = planRepository;
    }

    // ---- Plans ----

    @Transactional(readOnly = true)
    public List<BillingDtos.PlanResponse> plans() {
        return planRepository.findByActiveTrueOrderByMonthlyPriceAsc().stream()
                .map(p -> new BillingDtos.PlanResponse(p.getCode(), p.getDisplayName(), p.getMonthlyPrice(),
                        p.getMaxStudents(), p.getMaxTrainers(), p.isActive()))
                .toList();
    }

    /** Changing a plan affects FUTURE invoices only - invoices already issued keep the amount they
     * were raised at, which is why the amount is copied onto the invoice rather than looked up. */
    @Transactional
    @Auditable(action = "ACADEMY_PLAN_CHANGED", entityType = "academy")
    public void changePlan(UUID academyId, String planCode) {
        Academy academy = academyRepository.findById(academyId)
                .orElseThrow(() -> new ResourceNotFoundException("Academy not found: " + academyId));
        BillingPlan plan = planRepository.findById(planCode)
                .orElseThrow(() -> new BadRequestException("Unknown plan: " + planCode));
        academy.setPlan(plan.getCode());
        academyRepository.save(academy);
    }

    // ---- Invoices ----

    @Transactional(readOnly = true)
    public List<BillingDtos.InvoiceResponse> invoicesForPeriod(String period) {
        Map<UUID, String> names = academyNames();
        LocalDate today = LocalDate.now();
        return invoiceRepository.findByPeriodOrderByAmountDesc(period).stream()
                .map(i -> toResponse(i, names, today))
                .toList();
    }

    @Transactional(readOnly = true)
    public List<BillingDtos.InvoiceResponse> overdueInvoices() {
        Map<UUID, String> names = academyNames();
        LocalDate today = LocalDate.now();
        return invoiceRepository.findOverdue(today).stream()
                .map(i -> toResponse(i, names, today))
                .toList();
    }

    @Transactional(readOnly = true)
    public List<BillingDtos.InvoiceResponse> invoicesForAcademy(UUID academyId) {
        Map<UUID, String> names = academyNames();
        LocalDate today = LocalDate.now();
        return invoiceRepository.findByAcademyIdOrderByPeriodDesc(academyId).stream()
                .map(i -> toResponse(i, names, today))
                .toList();
    }

    /**
     * Raises this period's invoice for every ACTIVE academy. Idempotent by (academy, period): a
     * second run in the same month skips academies already invoiced rather than charging twice,
     * which matters because this is the kind of job that gets retried.
     *
     * @return how many invoices were newly created
     */
    @Transactional
    @Auditable(action = "INVOICES_GENERATED", entityType = "academy_invoice")
    public int generateInvoices(String period) {
        YearMonth month = parsePeriod(period);
        LocalDate issuedOn = month.atDay(1);
        LocalDate dueOn = issuedOn.plusDays(PAYMENT_TERM_DAYS);

        Map<String, BillingPlan> plans = plansByCode();
        int created = 0;

        for (Academy academy : academyRepository.findAll()) {
            if (academy.getStatus() != AcademyStatus.ACTIVE) {
                continue;
            }
            if (invoiceRepository.findByAcademyIdAndPeriod(academy.getId(), period).isPresent()) {
                continue;
            }
            BillingPlan plan = plans.get(academy.getPlan());
            if (plan == null) {
                log.warn("Academy {} is on unknown plan '{}' - skipping invoice for {}",
                        academy.getId(), academy.getPlan(), period);
                continue;
            }
            // A zero-price plan gets no invoice at all rather than a ₹0 one - an invoice for
            // nothing is noise in every list and dunning report it appears in.
            if (plan.getMonthlyPrice().compareTo(BigDecimal.ZERO) <= 0) {
                continue;
            }
            invoiceRepository.save(AcademyInvoice.builder()
                    .academyId(academy.getId())
                    .period(period)
                    .planCode(plan.getCode())
                    .amount(plan.getMonthlyPrice())
                    .status(InvoiceStatus.DUE)
                    .issuedOn(issuedOn)
                    .dueOn(dueOn)
                    .build());
            created++;
        }
        return created;
    }

    @Transactional
    @Auditable(action = "INVOICE_MARKED_PAID", entityType = "academy_invoice")
    public BillingDtos.InvoiceResponse markPaid(UUID invoiceId, BillingDtos.MarkPaidRequest request) {
        AcademyInvoice invoice = invoiceRepository.findById(invoiceId)
                .orElseThrow(() -> new ResourceNotFoundException("Invoice not found: " + invoiceId));
        if (invoice.getStatus() == InvoiceStatus.PAID) {
            throw new BadRequestException("This invoice is already marked paid");
        }
        invoice.setStatus(InvoiceStatus.PAID);
        invoice.setPaidAt(Instant.now());
        invoice.setPaidAmount(request.amount());
        invoice.setPaymentMethod(request.method());
        invoice.setPaymentRef(request.reference());
        invoice.setNote(request.note());
        invoice.setRecordedBy(TenantContext.currentUserId());
        invoiceRepository.save(invoice);
        return toResponse(invoice, academyNames(), LocalDate.now());
    }

    /** Writing a charge off is recorded, not deleted - a disappeared invoice makes the history
     * unreadable and looks like a bug the next time anyone reconciles. */
    @Transactional
    @Auditable(action = "INVOICE_WAIVED", entityType = "academy_invoice")
    public BillingDtos.InvoiceResponse waive(UUID invoiceId, String note) {
        AcademyInvoice invoice = invoiceRepository.findById(invoiceId)
                .orElseThrow(() -> new ResourceNotFoundException("Invoice not found: " + invoiceId));
        if (invoice.getStatus() == InvoiceStatus.PAID) {
            throw new BadRequestException("A paid invoice cannot be waived");
        }
        invoice.setStatus(InvoiceStatus.WAIVED);
        invoice.setNote(note);
        invoice.setRecordedBy(TenantContext.currentUserId());
        invoiceRepository.save(invoice);
        return toResponse(invoice, academyNames(), LocalDate.now());
    }

    // ---- Summary ----

    @Transactional(readOnly = true)
    public BillingDtos.BillingSummaryResponse summary() {
        LocalDate today = LocalDate.now();
        String period = YearMonth.from(today).toString();
        Map<String, BillingPlan> plans = plansByCode();

        Map<String, Long> academiesPerPlan = new HashMap<>();
        long paying = 0;
        long free = 0;
        BigDecimal mrr = BigDecimal.ZERO;

        for (Academy academy : academyRepository.findAll()) {
            // Suspended tenants are excluded: MRR is what the platform can expect to bill next
            // month, and a suspended academy isn't going to be billed.
            if (academy.getStatus() != AcademyStatus.ACTIVE) {
                continue;
            }
            BillingPlan plan = plans.get(academy.getPlan());
            if (plan == null) {
                continue;
            }
            academiesPerPlan.merge(plan.getCode(), 1L, Long::sum);
            if (plan.getMonthlyPrice().compareTo(BigDecimal.ZERO) > 0) {
                paying++;
                mrr = mrr.add(plan.getMonthlyPrice());
            } else {
                free++;
            }
        }

        List<BillingDtos.PlanBreakdown> byPlan = new ArrayList<>();
        academiesPerPlan.forEach((code, count) -> {
            BillingPlan plan = plans.get(code);
            byPlan.add(new BillingDtos.PlanBreakdown(code, plan.getDisplayName(), count,
                    plan.getMonthlyPrice().multiply(BigDecimal.valueOf(count))));
        });
        byPlan.sort(Comparator.comparing(BillingDtos.PlanBreakdown::monthlyValue).reversed());

        return new BillingDtos.BillingSummaryResponse(
                mrr,
                mrr.multiply(BigDecimal.valueOf(12)),
                invoiceRepository.sumBilledForPeriod(period),
                invoiceRepository.sumCollectedForPeriod(period),
                invoiceRepository.sumOverdue(today),
                invoiceRepository.findOverdue(today).size(),
                paying,
                free,
                period,
                byPlan);
    }

    // ---- helpers ----

    private BillingDtos.InvoiceResponse toResponse(AcademyInvoice invoice, Map<UUID, String> names, LocalDate today) {
        boolean overdue = invoice.isOverdue(today);
        long daysOverdue = overdue ? ChronoUnit.DAYS.between(invoice.getDueOn(), today) : 0;
        return new BillingDtos.InvoiceResponse(
                invoice.getId(), invoice.getAcademyId(), names.get(invoice.getAcademyId()),
                invoice.getPeriod(), invoice.getPlanCode(), invoice.getAmount(), invoice.getStatus().name(),
                invoice.getIssuedOn(), invoice.getDueOn(), overdue, daysOverdue,
                invoice.getPaidAt(), invoice.getPaidAmount(), invoice.getPaymentMethod(),
                invoice.getPaymentRef(), invoice.getNote());
    }

    private Map<UUID, String> academyNames() {
        Map<UUID, String> names = new HashMap<>();
        academyRepository.findAll().forEach(a -> names.put(a.getId(), a.getName()));
        return names;
    }

    private Map<String, BillingPlan> plansByCode() {
        Map<String, BillingPlan> plans = new HashMap<>();
        planRepository.findAll().forEach(p -> plans.put(p.getCode(), p));
        return plans;
    }

    private YearMonth parsePeriod(String period) {
        try {
            return YearMonth.parse(period);
        } catch (RuntimeException ex) {
            throw new BadRequestException("Period must look like 2026-07, got: " + period);
        }
    }
}
