package com.nest.app.fees.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.nest.app.fees.dto.ConfirmOnlinePaymentRequest;
import com.nest.app.fees.dto.OnlineOrderResponse;
import com.nest.app.fees.dto.PayFeeRequest;
import com.nest.app.fees.dto.PayFeeResponse;
import com.nest.app.fees.entity.FeeCategory;
import com.nest.app.fees.entity.FeeMode;
import com.nest.app.fees.entity.FeeTransaction;
import com.nest.app.fees.entity.PaymentOrder;
import com.nest.app.fees.gateway.RazorpayGateway;
import com.nest.app.fees.repository.FeeTransactionRepository;
import com.nest.app.fees.repository.PaymentOrderRepository;
import com.nest.common.exception.ConflictException;
import com.nest.common.exception.ForbiddenException;
import com.nest.common.exception.ResourceNotFoundException;
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
import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyMap;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class OnlinePaymentServiceTest {

    @Mock StudentPaymentService studentPaymentService;
    @Mock RazorpayGateway gateway;
    @Mock PaymentOrderRepository orderRepository;
    @Mock FeeTransactionRepository transactionRepository;

    private final UUID academyId = UUID.randomUUID();
    private final UUID membershipId = UUID.randomUUID();
    private final UUID userId = UUID.randomUUID();
    private final UUID feeTypeId = UUID.randomUUID();

    private OnlinePaymentService service;

    @BeforeEach
    void setUp() {
        TenantContext.set(new NestPrincipal(userId, "ishaan", Role.STUDENT,
                List.of(new MembershipClaim(membershipId, academyId, "Owleo", Role.STUDENT, Set.of(), Set.of())),
                membershipId));
        service = new OnlinePaymentService(studentPaymentService, gateway, orderRepository,
                transactionRepository, new ObjectMapper());
    }

    @AfterEach
    void tearDown() {
        TenantContext.clear();
    }

    private PaymentOrder order(UUID owner) {
        return PaymentOrder.builder()
                .id(UUID.randomUUID()).academyId(academyId).membershipId(owner).userId(userId)
                .category(FeeCategory.OTHER).feeTypeId(feeTypeId)
                .amount(new BigDecimal("500.00")).amountPaise(50000)
                .provider("RAZORPAY").providerOrderId("order_1").status(PaymentOrder.Status.CREATED)
                .build();
    }

    private void lock(PaymentOrder o) {
        when(orderRepository.lockByProviderOrderId("RAZORPAY", "order_1")).thenReturn(Optional.of(o));
    }

    private void saves() {
        when(transactionRepository.saveAndFlush(any())).thenAnswer(i -> {
            FeeTransaction t = i.getArgument(0);
            t.setId(UUID.randomUUID());
            return t;
        });
    }

    private static final ConfirmOnlinePaymentRequest CONFIRM =
            new ConfirmOnlinePaymentRequest("order_1", "pay_1", "sig");

    @Test
    void anOrderIsPricedFromTheLedgerAndPinnedBeforeTheStudentPays() {
        when(gateway.configured()).thenReturn(true);
        when(gateway.keyId()).thenReturn("rzp_test_abc");
        when(studentPaymentService.resolveDue(any())).thenReturn(new StudentPaymentService.Due(
                FeeCategory.OTHER, null, null, feeTypeId, null, new BigDecimal("499.50")));
        when(gateway.createOrder(anyLong(), anyString(), anyString(), anyMap())).thenReturn("order_9");

        OnlineOrderResponse response = service.createOrder(
                new PayFeeRequest(FeeCategory.OTHER, null, null, feeTypeId, null, "UPI"));

        assertThat(response.orderId()).isEqualTo("order_9");
        assertThat(response.amountPaise()).isEqualTo(49950);
        ArgumentCaptor<PaymentOrder> saved = ArgumentCaptor.forClass(PaymentOrder.class);
        verify(orderRepository).save(saved.capture());
        assertThat(saved.getValue().getMembershipId()).isEqualTo(membershipId);
        assertThat(saved.getValue().getAmountPaise()).isEqualTo(49950);
        assertThat(saved.getValue().getStatus()).isEqualTo(PaymentOrder.Status.CREATED);
    }

    @Test
    void withoutRazorpayCredentialsNoOrderIsCreated() {
        when(gateway.configured()).thenReturn(false);

        assertThatThrownBy(() -> service.createOrder(
                new PayFeeRequest(FeeCategory.OTHER, null, null, feeTypeId, null, "UPI")))
                .isInstanceOf(ConflictException.class);
        verify(orderRepository, never()).save(any());
    }

    @Test
    void aVerifiedConfirmationPostsTheOrdersAmountToTheLedgerOnce() {
        PaymentOrder o = order(membershipId);
        lock(o);
        when(gateway.verifyCheckoutSignature("order_1", "pay_1", "sig")).thenReturn(true);
        saves();

        PayFeeResponse response = service.confirm(CONFIRM);

        ArgumentCaptor<FeeTransaction> tx = ArgumentCaptor.forClass(FeeTransaction.class);
        verify(transactionRepository).saveAndFlush(tx.capture());
        assertThat(tx.getValue().getAmountPaid()).isEqualByComparingTo("500.00");
        assertThat(tx.getValue().getMode()).isEqualTo(FeeMode.GATEWAY);
        assertThat(tx.getValue().getGatewayRef()).isEqualTo("pay_1");
        assertThat(tx.getValue().getMembershipId()).isEqualTo(membershipId);
        assertThat(tx.getValue().getFeeTypeId()).isEqualTo(feeTypeId);
        assertThat(o.getStatus()).isEqualTo(PaymentOrder.Status.PAID);
        assertThat(o.getFeeTransactionId()).isNotNull();
        assertThat(response.gatewayRef()).isEqualTo("pay_1");
    }

    @Test
    void confirmingAnAlreadyPaidOrderPostsNothingMore() {
        PaymentOrder o = order(membershipId);
        UUID existing = UUID.randomUUID();
        o.setStatus(PaymentOrder.Status.PAID);
        o.setFeeTransactionId(existing);
        lock(o);
        when(gateway.verifyCheckoutSignature("order_1", "pay_1", "sig")).thenReturn(true);
        FeeTransaction prior = FeeTransaction.builder().id(existing).build();
        when(transactionRepository.findById(existing)).thenReturn(Optional.of(prior));

        PayFeeResponse response = service.confirm(CONFIRM);

        verify(transactionRepository, never()).saveAndFlush(any());
        assertThat(response.transactionId()).isEqualTo(existing);
    }

    @Test
    void aBadSignatureSettlesNothing() {
        lock(order(membershipId));
        when(gateway.verifyCheckoutSignature(any(), any(), any())).thenReturn(false);

        assertThatThrownBy(() -> service.confirm(CONFIRM)).isInstanceOf(ForbiddenException.class);
        verify(transactionRepository, never()).saveAndFlush(any());
    }

    @Test
    void anotherStudentsOrderLooksLikeItDoesNotExist() {
        lock(order(UUID.randomUUID()));

        assertThatThrownBy(() -> service.confirm(CONFIRM)).isInstanceOf(ResourceNotFoundException.class);
        verify(transactionRepository, never()).saveAndFlush(any());
    }

    private byte[] captured(long amount) {
        return ("{\"event\":\"payment.captured\",\"payload\":{\"payment\":{\"entity\":{\"id\":\"pay_1\","
                + "\"order_id\":\"order_1\",\"amount\":" + amount + ",\"status\":\"captured\"}}}}")
                .getBytes(StandardCharsets.UTF_8);
    }

    @Test
    void aWebhookWithABadSignatureIsRejectedBeforeAnythingIsRead() {
        when(gateway.verifyWebhookSignature(any(), eq("nope"))).thenReturn(false);

        assertThat(service.handleWebhook(captured(50000), "nope")).isFalse();
        verify(orderRepository, never()).lockByProviderOrderId(any(), any());
        verify(transactionRepository, never()).saveAndFlush(any());
    }

    @Test
    void aCapturedWebhookSettlesTheOrderWithoutTheBrowserEverReportingBack() {
        PaymentOrder o = order(membershipId);
        lock(o);
        when(gateway.verifyWebhookSignature(any(), any())).thenReturn(true);
        saves();

        assertThat(service.handleWebhook(captured(50000), "sig")).isTrue();

        verify(transactionRepository).saveAndFlush(any());
        assertThat(o.getStatus()).isEqualTo(PaymentOrder.Status.PAID);
        assertThat(o.getProviderPaymentId()).isEqualTo("pay_1");
    }

    @Test
    void aCapturedWebhookForADifferentAmountDoesNotSettleTheOrder() {
        PaymentOrder o = order(membershipId);
        lock(o);
        when(gateway.verifyWebhookSignature(any(), any())).thenReturn(true);

        assertThat(service.handleWebhook(captured(100), "sig")).isTrue();

        verify(transactionRepository, never()).saveAndFlush(any());
        assertThat(o.getStatus()).isEqualTo(PaymentOrder.Status.CREATED);
    }

    @Test
    void aWebhookForAnOrderWeNeverMadeIsAcknowledgedAndIgnored() {
        when(gateway.verifyWebhookSignature(any(), any())).thenReturn(true);
        when(orderRepository.lockByProviderOrderId("RAZORPAY", "order_1")).thenReturn(Optional.empty());

        assertThat(service.handleWebhook(captured(50000), "sig")).isTrue();
        verify(transactionRepository, never()).saveAndFlush(any());
    }

    @Test
    void rupeesBecomePaiseWithoutFloatingPointDrift() {
        assertThat(OnlinePaymentService.toPaise(new BigDecimal("0.10"))).isEqualTo(10);
        assertThat(OnlinePaymentService.toPaise(new BigDecimal("1999.99"))).isEqualTo(199999);
        assertThat(OnlinePaymentService.toPaise(new BigDecimal("1200"))).isEqualTo(120000);
    }
}
