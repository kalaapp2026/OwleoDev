package com.nest.app.fees.repository;

import com.nest.app.fees.entity.PaymentOrder;
import jakarta.persistence.LockModeType;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.Optional;
import java.util.UUID;

public interface PaymentOrderRepository extends JpaRepository<PaymentOrder, UUID> {

    /**
     * Row-locked, because the browser's confirmation and the gateway's webhook race each other and
     * both settle the same order. The loser blocks here until the winner commits, then sees PAID.
     */
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select o from PaymentOrder o where o.provider = :provider and o.providerOrderId = :orderId")
    Optional<PaymentOrder> lockByProviderOrderId(@Param("provider") String provider, @Param("orderId") String orderId);
}
