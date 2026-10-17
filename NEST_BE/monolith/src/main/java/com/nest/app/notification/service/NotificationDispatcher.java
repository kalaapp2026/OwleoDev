package com.nest.app.notification.service;

import com.nest.app.identity.entity.User;
import com.nest.app.identity.repository.UserRepository;
import com.nest.app.notification.entity.DeliveryStatus;
import com.nest.app.notification.entity.NotificationChannel;
import com.nest.app.notification.entity.NotificationDelivery;
import com.nest.app.notification.entity.NotificationEvent;
import com.nest.app.notification.entity.NotificationTemplate;
import com.nest.app.notification.entity.NotificationType;
import com.nest.app.notification.repository.NotificationDeliveryRepository;
import com.nest.app.notification.repository.NotificationTemplateRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.stereotype.Service;

import java.util.ArrayList;
import java.util.Collection;
import java.util.HashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import java.util.function.Function;
import java.util.stream.Collectors;

/**
 * The one call every business service makes when something notifiable happens:
 * {@code dispatcher.fire(NotificationEvent.X, userIds, params)}.
 *
 * <p>What actually goes out is decided by the Super Admin's template for that event - no template,
 * or a disabled one, means nothing is sent. The in-app row is written inline (so it commits or rolls
 * back with the business change); push and WhatsApp are handed to
 * {@link ExternalDeliveryListener} to run after commit.</p>
 *
 * <p>Never throws: a notification problem must not fail the fee payment or reschedule that
 * triggered it.</p>
 */
@Service
public class NotificationDispatcher {

    private static final Logger log = LoggerFactory.getLogger(NotificationDispatcher.class);

    private final NotificationTemplateRepository templateRepository;
    private final NotificationService notificationService;
    private final UserRepository userRepository;
    private final NotificationDeliveryRepository deliveryRepository;
    private final ApplicationEventPublisher publisher;

    public NotificationDispatcher(NotificationTemplateRepository templateRepository,
                                  NotificationService notificationService, UserRepository userRepository,
                                  NotificationDeliveryRepository deliveryRepository,
                                  ApplicationEventPublisher publisher) {
        this.templateRepository = templateRepository;
        this.notificationService = notificationService;
        this.userRepository = userRepository;
        this.deliveryRepository = deliveryRepository;
        this.publisher = publisher;
    }

    public void fire(NotificationEvent event, Collection<UUID> userIds, Map<String, String> params) {
        try {
            Optional<NotificationTemplate> template = templateRepository.findByEventKey(event.name())
                    .filter(NotificationTemplate::isEnabled);
            if (template.isEmpty() || userIds == null || userIds.isEmpty()) return;
            deliver(event, template.get(), userIds, params);
        } catch (RuntimeException e) {
            log.error("Notification {} could not be dispatched", event, e);
        }
    }

    /** Test send from the Super Admin console: ignores the template's enabled flag and the
     * recipient's preference switch, so "does this look right on my phone" always works. */
    public void fireTest(NotificationEvent event, NotificationTemplate template, UUID userId,
                         Map<String, String> sampleParams) {
        deliver(event, template, List.of(userId), sampleParams, true);
    }

    private void deliver(NotificationEvent event, NotificationTemplate t, Collection<UUID> userIds,
                         Map<String, String> params) {
        deliver(event, t, userIds, params, false);
    }

    private void deliver(NotificationEvent event, NotificationTemplate t, Collection<UUID> userIds,
                         Map<String, String> params, boolean ignorePreferences) {
        Map<UUID, User> users = userRepository.findAllById(new LinkedHashSet<>(userIds)).stream()
                .collect(Collectors.toMap(User::getId, Function.identity()));

        // WhatsApp template variables are positional, so order matters: they follow the order the
        // placeholders first appear in the body text.
        List<String> whatsappOrder = TemplateRenderer.placeholdersIn(t.getBodyTemplate());

        List<ExternalDeliveryRequested.Recipient> external = new ArrayList<>();
        for (UUID userId : new LinkedHashSet<>(userIds)) {
            User user = users.get(userId);
            if (user == null) continue;
            if (!ignorePreferences && !wantsEvent(user, event)) continue;

            Map<String, String> values = new HashMap<>(params == null ? Map.of() : params);
            values.put("recipientName", user.getFullName());
            String title = TemplateRenderer.render(t.getTitleTemplate(), values);
            String body = TemplateRenderer.render(t.getBodyTemplate(), values);

            if (t.isInAppEnabled()) {
                notificationService.notify(userId, event.getModule(), NotificationType.TEMPLATE_EVENT, title, body, null);
                log(userId, event, NotificationChannel.IN_APP, DeliveryStatus.SENT);
            }
            if (t.isPushEnabled() || t.isWhatsappEnabled()) {
                List<String> waParams = whatsappOrder.stream().map(n -> values.getOrDefault(n, "")).toList();
                external.add(new ExternalDeliveryRequested.Recipient(userId, title, body, waParams));
            }
        }
        if (!external.isEmpty()) {
            publisher.publishEvent(new ExternalDeliveryRequested(event.name(), t.isPushEnabled(),
                    t.isWhatsappEnabled(), t.getWhatsappTemplateName(), external));
        }
    }

    /** Settings > Notifications switches. Events with no preference key cannot be opted out of. */
    private boolean wantsEvent(User user, NotificationEvent event) {
        String key = event.getPreferenceKey();
        if (key == null) return true;
        if ("attendance".equals(key)) return user.isNotifyAttendance();
        if ("events".equals(key)) return user.isNotifyEvents();
        if ("study".equals(key)) return user.isNotifyStudy();
        return true;
    }

    private void log(UUID userId, NotificationEvent event, NotificationChannel channel, DeliveryStatus status) {
        deliveryRepository.save(NotificationDelivery.builder()
                .userId(userId).eventKey(event.name()).channel(channel).status(status).build());
    }
}
