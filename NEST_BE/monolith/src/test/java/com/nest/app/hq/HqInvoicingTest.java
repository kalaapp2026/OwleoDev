package com.nest.app.hq;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.nest.app.hq.service.HqBilling;
import com.nest.app.hq.service.HqChannels;
import com.nest.app.hq.service.HqInvoicing;
import com.nest.app.hq.service.HqNotifications;
import com.nest.app.notification.service.NotificationService;
import com.nest.common.exception.BadRequestException;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.mockito.junit.jupiter.MockitoSettings;
import org.mockito.quality.Strictness;
import org.springframework.jdbc.core.JdbcTemplate;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/** The bill schedule's dates and the checks on what an owner may change before a run. */
@ExtendWith(MockitoExtension.class)
@MockitoSettings(strictness = Strictness.LENIENT)
class HqInvoicingTest {

    @Mock
    private JdbcTemplate jdbc;
    @Mock
    private HqAudit audit;
    @Mock
    private HqBilling billing;
    @Mock
    private HqChannels channels;
    @Mock
    private HqNotifications templates;
    @Mock
    private NotificationService notifications;

    private HqInvoicing service() {
        return new HqInvoicing(jdbc, audit, billing, channels, templates, notifications, new ObjectMapper());
    }

    private static Map<String, Object> settings() {
        Map<String, Object> b = new LinkedHashMap<>();
        b.put("auto", true);
        b.put("gen", 5);
        b.put("sm", "after");
        b.put("after", 2);
        b.put("sday", 10);
        b.put("due", 14);
        b.put("ch", Map.of("em", true, "app", true, "wa", false));
        return b;
    }

    // ---- dates ----

    @Test
    void billsAreGeneratedSentAndDueOnTheDaysTheScheduleSays() {
        var after = new HqInvoicing.Settings(true, 5, "after", 2, 10, 14, true, true, false);
        var same = new HqInvoicing.Settings(true, 5, "same", 2, 10, 14, true, true, false);
        var fixed = new HqInvoicing.Settings(true, 5, "day", 2, 10, 14, true, true, false);

        assertThat(after.genDate("2026-11")).isEqualTo(LocalDate.of(2026, 11, 5));
        assertThat(after.sendDate("2026-11")).isEqualTo(LocalDate.of(2026, 11, 7));
        assertThat(after.dueDate("2026-11")).isEqualTo(LocalDate.of(2026, 11, 21));
        assertThat(same.sendDate("2026-11")).isEqualTo(LocalDate.of(2026, 11, 5));
        assertThat(fixed.sendDate("2026-11")).isEqualTo(LocalDate.of(2026, 11, 10));
        assertThat(fixed.dueDate("2026-11")).isEqualTo(LocalDate.of(2026, 11, 24));
    }

    @Test
    void aSendDaysAfterGeneratingMayRollIntoTheNextMonth() {
        var s = new HqInvoicing.Settings(true, 28, "after", 5, 10, 14, true, true, false);

        assertThat(s.sendDate("2026-11")).isEqualTo(LocalDate.of(2026, 12, 3));
    }

    // ---- schedule validation ----

    @Test
    void theScheduleRefusesDaysAndChannelsThatCannotWork() {
        var cases = new Object[][]{{"gen", 0}, {"gen", 29}, {"due", 0}, {"due", 90}, {"sm", "never"}, {"after", 0}, {"sday", 40}};
        for (Object[] c : cases) {
            Map<String, Object> b = settings();
            b.put((String) c[0], c[1]);
            assertThatThrownBy(() -> service().saveSettings(b)).as("%s=%s", c[0], c[1]).isInstanceOf(BadRequestException.class);
        }
        Map<String, Object> early = settings();
        early.put("sm", "day");
        early.put("sday", 3);
        assertThatThrownBy(() -> service().saveSettings(early)).hasMessageContaining("on or after");
        Map<String, Object> nothing = settings();
        nothing.put("ch", Map.of());
        assertThatThrownBy(() -> service().saveSettings(nothing)).hasMessageContaining("at least one way");
    }

    @Test
    void aValidScheduleIsSaved() {
        service().saveSettings(settings());

        verify(jdbc).update(org.mockito.ArgumentMatchers.contains("UPDATE hq_invoice_settings"), org.mockito.ArgumentMatchers.any(Object[].class));
    }

    // ---- what an owner may change for one academy ----

    private HqInvoicing withAcademy(UUID id) {
        Map<String, Object> a = new LinkedHashMap<>();
        a.put("id", id);
        a.put("name", "Nritya");
        a.put("plan", "STANDARD");
        when(billing.billable(anyString(), any())).thenReturn(List.of(a));
        when(billing.standardLines(eq(id), anyString())).thenReturn(List.of(new HqBilling.Line("PLAN", "Standard plan", new BigDecimal("2999"))));
        return service();
    }

    private static Map<String, Object> line(String kind, String label, int amount) {
        return Map.of("kind", kind, "label", label, "amount", amount, "standard", amount);
    }

    @Test
    void thePlanChargeCannotBeRemovedFromABill() {
        UUID id = UUID.randomUUID();
        Map<String, Object> b = new LinkedHashMap<>();
        b.put("lines", List.of(line("CUSTOM", "Setup help", 500)));

        assertThatThrownBy(() -> withAcademy(id).saveDraft(id, b)).isInstanceOf(BadRequestException.class).hasMessageContaining("plan charge");
    }

    @Test
    void aDiscountCannotBeMoreThanAHundredPercentOrEmpty() {
        UUID id = UUID.randomUUID();
        for (int bad : new int[]{0, 101}) {
            Map<String, Object> b = new LinkedHashMap<>();
            b.put("disc", Map.of("t", "pct", "val", bad, "months", 1));
            assertThatThrownBy(() -> withAcademy(id).saveDraft(id, b)).as("%s%%", bad).isInstanceOf(BadRequestException.class);
        }
    }

    @Test
    void anOfferThatIsNotRunningCannotBeChosen() {
        UUID id = UUID.randomUUID();
        Map<String, Object> b = new LinkedHashMap<>();
        b.put("disc", Map.of("t", "offer", "offer", UUID.randomUUID().toString(), "months", 1));

        assertThatThrownBy(() -> withAcademy(id).saveDraft(id, b)).isInstanceOf(BadRequestException.class).hasMessageContaining("not running");
    }

    @Test
    void aDiscountLastsAtMostTwelveBills() {
        UUID id = UUID.randomUUID();
        Map<String, Object> b = new LinkedHashMap<>();
        b.put("disc", Map.of("t", "pct", "val", 10, "months", 13));

        assertThatThrownBy(() -> withAcademy(id).saveDraft(id, b)).isInstanceOf(BadRequestException.class);
    }

    @Test
    void aBillThatChangesNothingLeavesNoDraftBehind() {
        UUID id = UUID.randomUUID();
        Map<String, Object> b = new LinkedHashMap<>();
        b.put("lines", List.of(line("PLAN", "Standard plan", 2999)));
        b.put("disc", Map.of("t", "none"));
        b.put("note", "");

        withAcademy(id).saveDraft(id, b);

        verify(jdbc).update("DELETE FROM hq_invoice_drafts WHERE academy_id = ?", id);
    }

    @Test
    void aChangedAmountIsRemembered() {
        UUID id = UUID.randomUUID();
        Map<String, Object> b = new LinkedHashMap<>();
        b.put("lines", List.of(Map.of("kind", "PLAN", "label", "Standard plan", "amount", 2499, "standard", 2999)));
        b.put("disc", Map.of("t", "none"));

        withAcademy(id).saveDraft(id, b);

        verify(jdbc).update(org.mockito.ArgumentMatchers.contains("INSERT INTO hq_invoice_drafts"), org.mockito.ArgumentMatchers.any(Object[].class));
    }
}
