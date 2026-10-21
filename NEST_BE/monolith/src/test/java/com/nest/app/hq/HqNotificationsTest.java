package com.nest.app.hq;

import com.nest.app.hq.service.HqChannels;
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

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.verifyNoInteractions;

/** What a notification template must satisfy before it is stored, and how details are filled in. */
@ExtendWith(MockitoExtension.class)
@MockitoSettings(strictness = Strictness.LENIENT)
class HqNotificationsTest {

    @Mock
    private JdbcTemplate jdbc;
    @Mock
    private HqAudit audit;
    @Mock
    private HqChannels channels;
    @Mock
    private NotificationService notifications;

    private HqNotifications service() {
        return new HqNotifications(jdbc, audit, channels, notifications);
    }

    /** A fees template that is valid, to be spoiled one field at a time. */
    private static Map<String, Object> fees() {
        Map<String, Object> b = new LinkedHashMap<>();
        b.put("module", "fees");
        b.put("event", "overdue");
        b.put("name", "Fee overdue");
        b.put("audience", "student");
        b.put("on", true);
        b.put("ch", Map.of("inapp", true, "push", true));
        b.put("title", "Fee overdue");
        b.put("body", "Hi {student}, {amount} for {course} was due on {due_date}.");
        b.put("timing", 2);
        return b;
    }

    @Test
    void aDetailTheModuleDoesNotHaveIsRefusedByName() {
        Map<String, Object> b = fees();
        b.put("body", "Hi {student}, your {venue} is booked.");

        assertThatThrownBy(() -> service().save(null, b)).isInstanceOf(BadRequestException.class)
                .hasMessageContaining("{venue}").hasMessageContaining("Fees");
        verifyNoInteractions(jdbc);
    }

    @Test
    void aTemplateThatIsOnNeedsATitleAMessageAndAChannel() {
        Map<String, Object> noBody = fees();
        noBody.put("body", " ");
        Map<String, Object> noChannel = fees();
        noChannel.put("ch", Map.of());

        assertThatThrownBy(() -> service().save(null, noBody)).isInstanceOf(BadRequestException.class).hasMessageContaining("title and message");
        assertThatThrownBy(() -> service().save(null, noChannel)).isInstanceOf(BadRequestException.class).hasMessageContaining("channel");
    }

    @Test
    void aTemplateThatIsOffMayBeLeftBlank() {
        Map<String, Object> b = fees();
        b.put("on", false);
        b.put("title", "");
        b.put("body", "");
        b.put("ch", Map.of());

        // Passes validation; the insert is attempted (the mocked database answers nothing).
        service().save(null, b);
        org.mockito.Mockito.verify(jdbc).update(org.mockito.ArgumentMatchers.startsWith("INSERT INTO hq_notification_templates"), org.mockito.ArgumentMatchers.any(Object[].class));
    }

    @Test
    void aSignInCodeMustCarryTheCodeOrItWillNeverReachThem() {
        Map<String, Object> b = new LinkedHashMap<>();
        b.put("module", "security");
        b.put("event", "otp");
        b.put("name", "Sign-in code");
        b.put("on", true);
        b.put("ch", Map.of("mail", true));
        b.put("title", "Your sign-in code");
        b.put("body", "Welcome to {academy}. This code works for {minutes} minutes.");
        b.put("timing", 10);

        assertThatThrownBy(() -> service().save(null, b)).isInstanceOf(BadRequestException.class).hasMessageContaining("{otp}");
    }

    @Test
    void signInMessagesGoByEmailOrWhatsAppNeverInTheApp() {
        Map<String, Object> b = new LinkedHashMap<>();
        b.put("module", "security");
        b.put("event", "changed");
        b.put("name", "Password changed");
        b.put("on", false);
        b.put("ch", Map.of("inapp", true));
        b.put("title", "Changed");
        b.put("body", "Hi {name}, your password was changed.");

        assertThatThrownBy(() -> service().save(null, b)).isInstanceOf(BadRequestException.class).hasMessageContaining("email or WhatsApp");
    }

    @Test
    void aTimingMustBeAWholeNumberAboveZero() {
        for (Object bad : new Object[]{"soon", 0, -3, 5000}) {
            Map<String, Object> b = fees();
            b.put("timing", bad);
            assertThatThrownBy(() -> service().save(null, b)).as("timing %s", bad).isInstanceOf(BadRequestException.class).hasMessageContaining("whole number");
        }
    }

    @Test
    void aSecurityTemplateKeepsAtLeastOneTypeOfUser() {
        Map<String, Object> b = new LinkedHashMap<>();
        b.put("module", "security");
        b.put("event", "changed");
        b.put("name", "Password changed");
        b.put("ch", Map.of("mail", true));
        b.put("title", "Changed");
        b.put("body", "Hi {name}, your password was changed.");
        b.put("types", List.of());

        assertThatThrownBy(() -> service().save(null, b)).isInstanceOf(BadRequestException.class).hasMessageContaining("type of user");
    }

    @Test
    void aParentMessageWrittenSeparatelyNeedsItsOwnWording() {
        Map<String, Object> b = fees();
        b.put("par", Map.of("on", true, "min", true, "diff", true, "title", "", "body", ""));

        assertThatThrownBy(() -> service().save(null, b)).isInstanceOf(BadRequestException.class).hasMessageContaining("parent");
    }

    @Test
    void detailsAreFilledAndAnUnknownOneIsLeftVisible() {
        String out = HqNotifications.fill("Hi {student}, {amount} is due. {nope}", Map.of("student", "Aanya", "amount", "₹2,400"));

        assertThat(out).isEqualTo("Hi Aanya, ₹2,400 is due. {nope}");
    }
}
