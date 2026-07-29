package com.nest.app.billing.repository;

import com.nest.app.billing.entity.AcademyInvoice;
import com.nest.app.billing.entity.InvoiceStatus;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

public interface AcademyInvoiceRepository extends JpaRepository<AcademyInvoice, UUID> {

    Optional<AcademyInvoice> findByAcademyIdAndPeriod(UUID academyId, String period);

    List<AcademyInvoice> findByAcademyIdOrderByPeriodDesc(UUID academyId);

    List<AcademyInvoice> findByStatusOrderByDueOnAsc(InvoiceStatus status);

    List<AcademyInvoice> findByPeriodOrderByAmountDesc(String period);

    /** Everything still unpaid past its due date - the dunning list the console opens on. */
    @Query("select i from AcademyInvoice i where i.status = 'DUE' and i.dueOn < :today order by i.dueOn asc")
    List<AcademyInvoice> findOverdue(@Param("today") LocalDate today);

    @Query("select coalesce(sum(i.amount), 0) from AcademyInvoice i where i.status = 'DUE' and i.dueOn < :today")
    BigDecimal sumOverdue(@Param("today") LocalDate today);

    @Query("select coalesce(sum(i.paidAmount), 0) from AcademyInvoice i where i.status = 'PAID' and i.period = :period")
    BigDecimal sumCollectedForPeriod(@Param("period") String period);

    @Query("select coalesce(sum(i.amount), 0) from AcademyInvoice i where i.period = :period")
    BigDecimal sumBilledForPeriod(@Param("period") String period);

    long countByStatus(InvoiceStatus status);
}
