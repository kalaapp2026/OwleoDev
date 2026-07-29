package com.nest.app.billing.repository;

import com.nest.app.billing.entity.BillingPlan;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface BillingPlanRepository extends JpaRepository<BillingPlan, String> {

    List<BillingPlan> findByActiveTrueOrderByMonthlyPriceAsc();
}
