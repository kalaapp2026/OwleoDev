package com.nest.app.billing;

import com.nest.app.billing.service.SubscriptionPaymentService;
import com.nest.app.fees.gateway.RazorpayGateway;
import com.nest.app.hq.service.HqBilling;
import com.nest.app.notification.service.NotificationService;
import com.nest.common.exception.BadRequestException;
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
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.mockito.junit.jupiter.MockitoSettings;
import org.mockito.quality.Strictness;
import org.springframework.jdbc.core.JdbcTemplate;

import java.math.BigDecimal;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/** An academy admin paying Owleo's bill: the amount is the server's, and money is posted once. */
@ExtendWith(MockitoExtension.class)
@MockitoSettings(strictness = Strictness.LENIENT)
class SubscriptionPaymentServiceTest {

    @Mock
    private JdbcTemplate jdbc;
    @Mock
    private RazorpayGateway gateway;
    @Mock
    private HqBilling billing;
    @Mock
    private NotificationService notifications;

    private final UUID academy = UUID.randomUUID(), user = UUID.randomUUID(), invoice = UUID.randomUUID();

    private SubscriptionPaymentService service() {
        return new SubscriptionPaymentService(jdbc, gateway, billing, notifications);
    }

    @BeforeEach
    void signIn() {
        UUID membership = UUID.randomUUID();
        TenantContext.set(new NestPrincipal(user, "admin", Role.ACADEMY_ADMIN,
                List.of(new MembershipClaim(membership, academy, "Nritya", Role.ACADEMY_ADMIN, Set.of(), Set.of())), membership));
        when(gateway.configured()).thenReturn(true);
        when(gateway.keyId()).thenReturn("rzp_test_abc");
        when(billing.balance(invoice)).thenReturn(new BigDecimal("2949"));
    }

    @AfterEach
    void signOut() {
        TenantContext.clear();
    }

    private void invoiceOf(UUID owner, String status) {
        Map<String, Object> row = new LinkedHashMap<>();
        row.put("id", invoice);
        row.put("academy_id", owner);
        row.put("number", "INV-2611-007");
        row.put("status", status);
        when(jdbc.queryForList(org.mockito.ArgumentMatchers.contains("FROM academy_invoices WHERE id"), any(Object[].class))).thenReturn(List.of(row));
    }

    private Map<String, Object> order(UUID owner, String status) {
        Map<String, Object> o = new LinkedHashMap<>();
        o.put("id", UUID.randomUUID());
        o.put("invoice_id", invoice);
        o.put("academy_id", owner);
        o.put("user_id", user);
        o.put("amount", new BigDecimal("2949"));
        o.put("amount_paise", 294900L);
        o.put("status", status);
        return o;
    }

    private void orderFound(Map<String, Object> o) {
        when(jdbc.queryForList(org.mockito.ArgumentMatchers.contains("FROM invoice_payment_orders"), any(Object[].class))).thenReturn(List.of(o));
    }

    // ---- starting a payment ----

    @Test
    void thereIsNoCheckoutUntilTheGatewayIsSetUp() {
        when(gateway.configured()).thenReturn(false);

        assertThatThrownBy(() -> service().createOrder(invoice)).isInstanceOf(ConflictException.class).hasMessageContaining("not switched on");
    }

    @Test
    void anotherAcademysBillLooksLikeItDoesNotExist() {
        invoiceOf(UUID.randomUUID(), "DUE");

        assertThatThrownBy(() -> service().createOrder(invoice)).isInstanceOf(ResourceNotFoundException.class);
        verify(gateway, never()).createOrder(anyLong(), anyString(), anyString(), any());
    }

    @Test
    void aPaidOrWaivedBillCannotBePaidAgain() {
        invoiceOf(academy, "WAIVED");
        assertThatThrownBy(() -> service().createOrder(invoice)).isInstanceOf(BadRequestException.class).hasMessageContaining("waived");

        invoiceOf(academy, "PAID");
        when(billing.balance(invoice)).thenReturn(BigDecimal.ZERO);
        assertThatThrownBy(() -> service().createOrder(invoice)).isInstanceOf(BadRequestException.class).hasMessageContaining("already paid");
    }

    @Test
    void theCheckoutIsForTheBillsBalanceAsTheServerWorksItOut() {
        invoiceOf(academy, "DUE");
        when(gateway.createOrder(anyLong(), anyString(), anyString(), any())).thenReturn("order_123");

        Map<String, Object> out = service().createOrder(invoice);

        assertThat(out.get("orderId")).isEqualTo("order_123");
        assertThat(out.get("amountPaise")).isEqualTo(294900L);
        verify(gateway).createOrder(eq(294900L), eq("INR"), anyString(), any());
    }

    // ---- confirming ----

    @Test
    void aPaymentThatCannotBeVerifiedPostsNothing() {
        orderFound(order(academy, "CREATED"));
        when(gateway.verifyCheckoutSignature("order_1", "pay_1", "bad")).thenReturn(false);

        assertThatThrownBy(() -> service().confirm("order_1", "pay_1", "bad")).isInstanceOf(ForbiddenException.class);
        verify(billing, never()).recordPayment(any(), any(), anyString(), anyString(), any(), anyString(), any());
    }

    @Test
    void anotherAcademysOrderIsNotFound() {
        orderFound(order(UUID.randomUUID(), "CREATED"));

        assertThatThrownBy(() -> service().confirm("order_1", "pay_1", "sig")).isInstanceOf(ResourceNotFoundException.class);
    }

    @Test
    void aVerifiedPaymentIsRecordedOnceAsOnline() {
        orderFound(order(academy, "CREATED"));
        when(gateway.verifyCheckoutSignature("order_1", "pay_1", "good")).thenReturn(true);
        when(billing.recordPayment(eq(invoice), any(), anyString(), anyString(), any(), anyString(), any())).thenReturn(UUID.randomUUID());

        Map<String, Object> out = service().confirm("order_1", "pay_1", "good");

        verify(billing).recordPayment(eq(invoice), eq(new BigDecimal("2949")), eq("Razorpay"), eq("pay_1"), eq(null), eq("ONLINE"), eq(user));
        assertThat(out.get("amount")).isEqualTo(new BigDecimal("2949"));
    }

    @Test
    void confirmingAnAlreadyPaidOrderAgainPostsNothing() {
        orderFound(order(academy, "PAID"));
        when(gateway.verifyCheckoutSignature("order_1", "pay_1", "good")).thenReturn(true);

        Map<String, Object> out = service().confirm("order_1", "pay_1", "good");

        assertThat(out.get("alreadySettled")).isEqualTo(true);
        verify(billing, never()).recordPayment(any(), any(), anyString(), anyString(), any(), anyString(), any());
    }

    @Test
    void moneyThatArrivesAfterTheBillWasSettledElsewhereIsFlaggedNotLost() {
        orderFound(order(academy, "CREATED"));
        when(gateway.verifyCheckoutSignature("order_1", "pay_1", "good")).thenReturn(true);
        when(billing.balance(invoice)).thenReturn(BigDecimal.ZERO);

        Map<String, Object> out = service().confirm("order_1", "pay_1", "good");

        verify(billing, never()).recordPayment(any(), any(), anyString(), anyString(), any(), anyString(), any());
        assertThat(String.valueOf(out.get("note"))).contains("Refund");
    }

    // ---- the webhook ----

    @Test
    void aWebhookForAnOrderThatIsNotOursIsLeftAlone() {
        when(jdbc.queryForList(org.mockito.ArgumentMatchers.contains("FROM invoice_payment_orders"), any(Object[].class))).thenReturn(List.of());

        assertThat(service().handleWebhook("payment.captured", "order_x", "pay_x", 100)).isFalse();
    }

    @Test
    void aWebhookWithTheWrongAmountSettlesNothing() {
        orderFound(order(academy, "CREATED"));

        assertThat(service().handleWebhook("payment.captured", "order_1", "pay_1", 100)).isTrue();
        verify(billing, never()).recordPayment(any(), any(), anyString(), anyString(), any(), anyString(), any());
    }

    @Test
    void aWebhookWithTheRightAmountSettlesTheBill() {
        orderFound(order(academy, "CREATED"));
        when(billing.recordPayment(eq(invoice), any(), anyString(), anyString(), any(), anyString(), any())).thenReturn(UUID.randomUUID());

        assertThat(service().handleWebhook("payment.captured", "order_1", "pay_1", 294900)).isTrue();
        verify(billing).recordPayment(eq(invoice), eq(new BigDecimal("2949")), eq("Razorpay"), eq("pay_1"), eq(null), eq("ONLINE"), eq(user));
    }
}
