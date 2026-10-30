package com.nest.app.hq;

import com.nest.app.fees.gateway.RazorpayGateway;
import com.nest.app.hq.service.HqPayments;
import com.nest.common.exception.BadRequestException;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.mockito.junit.jupiter.MockitoSettings;
import org.mockito.quality.Strictness;
import org.springframework.jdbc.core.JdbcTemplate;

import java.math.BigDecimal;
import java.sql.Timestamp;
import java.time.LocalDate;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

/** The payments history: what it refuses, how it counts, and the account mapping's states. */
@ExtendWith(MockitoExtension.class)
@MockitoSettings(strictness = Strictness.LENIENT)
class HqPaymentsTest {

    @Mock
    private JdbcTemplate jdbc;
    @Mock
    private RazorpayGateway gateway;

    private HqPayments payments() {
        return new HqPayments(jdbc, gateway);
    }

    private static Map<String, Object> row(String type, String status, String source, String academy, UUID academyId, String amount, LocalDate day) {
        Map<String, Object> r = new LinkedHashMap<>();
        r.put("type", type);
        r.put("id", UUID.randomUUID().toString());
        r.put("at", Timestamp.valueOf(day.atTime(10, 0)));
        r.put("academy_id", academyId);
        r.put("academy", academy);
        r.put("ref_no", "INV-1");
        r.put("amount", new BigDecimal(amount));
        r.put("mode", "Razorpay");
        r.put("reference", "pay_1");
        r.put("source", source);
        r.put("status", status);
        r.put("by_name", "Someone");
        r.put("note", "");
        return r;
    }

    @Test
    void anUnknownFilterIsRefusedBeforeTheDatabaseIsTouched() {
        assertThatThrownBy(() -> payments().transactions(null, "weird", "all", "all", null, null)).isInstanceOf(BadRequestException.class);
        assertThatThrownBy(() -> payments().transactions(null, "all", "pending", "all", null, null)).isInstanceOf(BadRequestException.class);
        assertThatThrownBy(() -> payments().transactions("October", "all", "all", "all", null, null)).isInstanceOf(BadRequestException.class);
        verifyNoInteractions(jdbc);
    }

    @Test
    void onlyPaidMoneyIsCountedAndOnlineIsSeparatedFromByHand() {
        UUID a = UUID.randomUUID();
        LocalDate today = LocalDate.now();
        when(jdbc.queryForList(anyString())).thenReturn(List.of(
                row("subscription", "paid", "online", "Nritya", a, "1000", today),
                row("subscription", "paid", "manual", "Nritya", a, "500", today),
                row("subscription", "started", "online", "Nritya", a, "700", today),
                row("subscription", "failed", "online", "Nritya", a, "300", today),
                row("student", "paid", "online", "Nritya", a, "200", today)));

        @SuppressWarnings("unchecked") Map<String, Object> k = (Map<String, Object>) payments().transactions(null, "all", "all", "all", null, null).get("kpis");

        assertThat(k.get("subscription")).isEqualTo(new BigDecimal("1500"));
        assertThat(k.get("online")).isEqualTo(new BigDecimal("1000"));
        assertThat(k.get("manual")).isEqualTo(new BigDecimal("500"));
        assertThat(k.get("student")).isEqualTo(new BigDecimal("200"));
        assertThat(k.get("started")).isEqualTo(1);
        assertThat(k.get("failed")).isEqualTo(1);
    }

    @Test
    void filtersNarrowTheListAndTheCounts() {
        UUID a = UUID.randomUUID(), b = UUID.randomUUID();
        LocalDate today = LocalDate.now();
        when(jdbc.queryForList(anyString())).thenReturn(List.of(
                row("subscription", "paid", "online", "Nritya", a, "1000", today),
                row("subscription", "paid", "manual", "Natya", b, "500", today),
                row("subscription", "paid", "manual", "Natya", b, "250", today.minusMonths(2))));

        @SuppressWarnings("unchecked") List<Map<String, Object>> items = (List<Map<String, Object>>) payments().transactions(null, "all", "all", "manual", b.toString(), null).get("items");
        assertThat(items).hasSize(2);
        @SuppressWarnings("unchecked") List<Map<String, Object>> thisMonth = (List<Map<String, Object>>) payments().transactions(today.toString().substring(0, 7), "all", "all", "manual", b.toString(), null).get("items");
        assertThat(thisMonth).hasSize(1);
        @SuppressWarnings("unchecked") List<Map<String, Object>> found = (List<Map<String, Object>>) payments().transactions(null, "all", "all", "all", null, "natya").get("items");
        assertThat(found).hasSize(2);
    }

    @Test
    void anAcademyIsMappedOnlyWhenItHasBothABankAccountAndAGatewayAccount() {
        when(gateway.keyId()).thenReturn("rzp_live_abcd1234");
        when(gateway.configured()).thenReturn(true);
        Map<String, Object> mapped = acct("A", "bank-1", "Razorpay", "acc_123456");
        Map<String, Object> bankOnly = acct("B", "bank-2", null, null);
        Map<String, Object> none = acct("C", null, null, null);
        when(jdbc.queryForList(org.mockito.ArgumentMatchers.contains("FROM academies a LEFT JOIN academy_bank_accounts"))).thenReturn(List.of(mapped, bankOnly, none));

        Map<String, Object> out = payments().accounts();

        @SuppressWarnings("unchecked") Map<String, Object> counts = (Map<String, Object>) out.get("counts");
        assertThat(counts).containsEntry("mapped", 1).containsEntry("bank", 1).containsEntry("none", 1);
        @SuppressWarnings("unchecked") Map<String, Object> owleo = (Map<String, Object>) out.get("owleo");
        assertThat(owleo).containsEntry("connected", true).containsEntry("mode", "live");
        assertThat(owleo.get("keyHint")).isEqualTo("…1234");
    }

    private static Map<String, Object> acct(String name, String bankId, String gateway, String merchant) {
        Map<String, Object> r = new LinkedHashMap<>();
        r.put("id", UUID.randomUUID());
        r.put("name", name);
        r.put("plan", "BASIC");
        r.put("demo_ends_on", null);
        r.put("status", "ACTIVE");
        r.put("bank_id", bankId == null ? null : UUID.randomUUID());
        r.put("bank", "HDFC");
        r.put("holder", "Holder");
        r.put("account_last4", "1234");
        r.put("ifsc", "HDFC0001");
        r.put("gateway", gateway);
        r.put("merchant_id", merchant);
        r.put("subscription_paid", BigDecimal.ZERO);
        r.put("last_paid", null);
        r.put("student_collected", BigDecimal.ZERO);
        return r;
    }
}
