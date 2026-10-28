package com.nest.app.notification.service;

import com.nest.app.identity.entity.User;
import com.nest.app.identity.repository.UserRepository;
import com.nest.app.notification.entity.NotificationEvent;
import com.nest.app.notification.entity.NotificationModule;
import com.nest.app.notification.entity.NotificationTemplate;
import com.nest.app.notification.entity.NotificationType;
import com.nest.app.notification.repository.NotificationDeliveryRepository;
import com.nest.app.notification.repository.NotificationTemplateRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.context.ApplicationEventPublisher;

import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class NotificationDispatcherTest {

    @Mock private NotificationTemplateRepository templateRepository;
    @Mock private NotificationService notificationService;
    @Mock private UserRepository userRepository;
    @Mock private NotificationDeliveryRepository deliveryRepository;
    @Mock private ApplicationEventPublisher publisher;

    private NotificationDispatcher dispatcher;
    private final UUID userId = UUID.randomUUID();

    @BeforeEach
    void setUp() {
        dispatcher = new NotificationDispatcher(templateRepository, notificationService, userRepository,
                deliveryRepository, publisher);
    }

    private NotificationTemplate template(boolean inApp, boolean push, boolean whatsapp, boolean enabled) {
        return NotificationTemplate.builder()
                .eventKey(NotificationEvent.CLASS_CANCELLED.name())
                .titleTemplate("Cancelled: {{batchName}}")
                .bodyTemplate("Hi {{recipientName}}, {{batchName}} on {{date}} is off. {{reason}}")
                .inAppEnabled(inApp).pushEnabled(push).whatsappEnabled(whatsapp)
                .whatsappTemplateName(whatsapp ? "class_cancelled" : null)
                .enabled(enabled).build();
    }

    private User user(boolean notifyAttendance) {
        User u = new User();
        u.setId(userId);
        u.setFullName("Asha");
        u.setNotifyAttendance(notifyAttendance);
        return u;
    }

    @Test
    void noTemplateMeansNothingIsSent() {
        when(templateRepository.findByEventKey("CLASS_CANCELLED")).thenReturn(Optional.empty());

        dispatcher.fire(NotificationEvent.CLASS_CANCELLED, List.of(userId), Map.of());

        verify(notificationService, never()).notify(any(), any(), any(), any(), any(), any());
        verify(publisher, never()).publishEvent(any(Object.class));
    }

    @Test
    void disabledTemplateIsSilent() {
        when(templateRepository.findByEventKey("CLASS_CANCELLED"))
                .thenReturn(Optional.of(template(true, true, true, false)));

        dispatcher.fire(NotificationEvent.CLASS_CANCELLED, List.of(userId), Map.of());

        verify(notificationService, never()).notify(any(), any(), any(), any(), any(), any());
    }

    @Test
    void rendersPerRecipientAndWritesInAppCopy() {
        when(templateRepository.findByEventKey("CLASS_CANCELLED"))
                .thenReturn(Optional.of(template(true, false, false, true)));
        when(userRepository.findAllById(any())).thenReturn(List.of(user(true)));

        dispatcher.fire(NotificationEvent.CLASS_CANCELLED, List.of(userId),
                Map.of("batchName", "Kathak A", "date", "12 Oct", "reason", "Trainer unwell."));

        verify(notificationService).notify(eq(userId), eq(NotificationModule.ERP), eq(NotificationType.TEMPLATE_EVENT),
                eq("Cancelled: Kathak A"), eq("Hi Asha, Kathak A on 12 Oct is off. Trainer unwell."), eq(null));
        verify(publisher, never()).publishEvent(any(Object.class));
    }

    @Test
    void pushAndWhatsAppGoOutAsOneDeferredEventWithOrderedParameters() {
        when(templateRepository.findByEventKey("CLASS_CANCELLED"))
                .thenReturn(Optional.of(template(false, true, true, true)));
        when(userRepository.findAllById(any())).thenReturn(List.of(user(true)));

        dispatcher.fire(NotificationEvent.CLASS_CANCELLED, List.of(userId),
                Map.of("batchName", "Kathak A", "date", "12 Oct", "reason", "Rain."));

        ArgumentCaptor<Object> captor = ArgumentCaptor.forClass(Object.class);
        verify(publisher).publishEvent(captor.capture());
        ExternalDeliveryRequested sent = (ExternalDeliveryRequested) captor.getValue();
        assertTrue(sent.push());
        assertTrue(sent.whatsapp());
        assertEquals("class_cancelled", sent.whatsappTemplateName());
        // Variable order follows first appearance in the body: recipientName, batchName, date, reason.
        assertEquals(List.of("Asha", "Kathak A", "12 Oct", "Rain."), sent.recipients().get(0).whatsappParameters());
        verify(notificationService, never()).notify(any(), any(), any(), any(), any(), any());
    }

    @Test
    void respectsTheRecipientsPreferenceSwitch() {
        NotificationTemplate t = template(true, false, false, true);
        t.setEventKey(NotificationEvent.ATTENDANCE_ABSENT.name());
        when(templateRepository.findByEventKey("ATTENDANCE_ABSENT")).thenReturn(Optional.of(t));
        when(userRepository.findAllById(any())).thenReturn(List.of(user(false)));

        dispatcher.fire(NotificationEvent.ATTENDANCE_ABSENT, List.of(userId), Map.of());

        verify(notificationService, never()).notify(any(), any(), any(), any(), any(), any());
    }

    @Test
    void aFailureNeverEscapesToTheBusinessCaller() {
        when(templateRepository.findByEventKey(any())).thenThrow(new IllegalStateException("db down"));

        dispatcher.fire(NotificationEvent.CLASS_CANCELLED, List.of(userId), Map.of());

        assertFalse(false); // reaching here without an exception is the assertion
    }

    @Test
    void fireOrDefaultSendsWithBuiltInWordingWhenNoTemplateExists() {
        when(templateRepository.findByEventKey("CLASS_REMINDER")).thenReturn(Optional.empty());
        when(userRepository.findAllById(any())).thenReturn(List.of(user(true)));

        int reached = dispatcher.fireOrDefault(NotificationEvent.CLASS_REMINDER, List.of(userId),
                Map.of("batchName", "Kathak A", "courseName", "Kathak", "date", "12 Oct", "time", "5:30 PM"));

        assertEquals(1, reached);
        // The person pressed a button, so silence would look like a bug.
        verify(notificationService).notify(eq(userId), eq(NotificationModule.ERP), eq(NotificationType.TEMPLATE_EVENT),
                eq("Class reminder"),
                eq("Hi Asha, reminder: this is your next class - Kathak A (Kathak) on 12 Oct at 5:30 PM."), eq(null));
        // Push goes out too, as one deferred event.
        verify(publisher).publishEvent(any(Object.class));
    }

    @Test
    void fireOrDefaultHonoursATemplateTheSuperAdminSwitchedOff() {
        NotificationTemplate off = template(true, true, false, false);
        off.setEventKey(NotificationEvent.CLASS_REMINDER.name());
        when(templateRepository.findByEventKey("CLASS_REMINDER")).thenReturn(Optional.of(off));

        int reached = dispatcher.fireOrDefault(NotificationEvent.CLASS_REMINDER, List.of(userId), Map.of());

        assertEquals(0, reached);
        verify(notificationService, never()).notify(any(), any(), any(), any(), any(), any());
    }

    @Test
    void fireOrDefaultUsesASavedTemplatesWording() {
        NotificationTemplate custom = template(true, false, false, true);
        custom.setEventKey(NotificationEvent.CLASS_REMINDER.name());
        custom.setTitleTemplate("Heads up: {{batchName}}");
        custom.setBodyTemplate("{{recipientName}}, class at {{time}}");
        when(templateRepository.findByEventKey("CLASS_REMINDER")).thenReturn(Optional.of(custom));
        when(userRepository.findAllById(any())).thenReturn(List.of(user(true)));

        dispatcher.fireOrDefault(NotificationEvent.CLASS_REMINDER, List.of(userId),
                Map.of("batchName", "Kathak A", "time", "5:30 PM"));

        verify(notificationService).notify(eq(userId), eq(NotificationModule.ERP), eq(NotificationType.TEMPLATE_EVENT),
                eq("Heads up: Kathak A"), eq("Asha, class at 5:30 PM"), eq(null));
    }
}
