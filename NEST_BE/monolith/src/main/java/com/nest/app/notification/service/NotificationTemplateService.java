package com.nest.app.notification.service;

import com.nest.app.identity.entity.User;
import com.nest.app.identity.repository.UserRepository;
import com.nest.app.notification.channel.PushSender;
import com.nest.app.notification.channel.WhatsAppSender;
import com.nest.app.notification.dto.NotificationTemplateDtos.CatalogResponse;
import com.nest.app.notification.dto.NotificationTemplateDtos.ChannelStatus;
import com.nest.app.notification.dto.NotificationTemplateDtos.DeliveryView;
import com.nest.app.notification.dto.NotificationTemplateDtos.EventView;
import com.nest.app.notification.dto.NotificationTemplateDtos.SaveRequest;
import com.nest.app.notification.dto.NotificationTemplateDtos.TemplateView;
import com.nest.app.notification.entity.NotificationDelivery;
import com.nest.app.notification.entity.NotificationEvent;
import com.nest.app.notification.entity.NotificationTemplate;
import com.nest.app.notification.repository.NotificationDeliveryRepository;
import com.nest.app.notification.repository.NotificationTemplateRepository;
import com.nest.common.exception.BadRequestException;
import com.nest.common.exception.ResourceNotFoundException;
import org.springframework.data.domain.PageRequest;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.util.Arrays;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.function.Function;
import java.util.stream.Collectors;

/** Super Admin CRUD over notification templates. */
@Service
public class NotificationTemplateService {

    private final NotificationTemplateRepository templateRepository;
    private final NotificationDeliveryRepository deliveryRepository;
    private final UserRepository userRepository;
    private final NotificationDispatcher dispatcher;
    private final PushSender pushSender;
    private final WhatsAppSender whatsAppSender;

    public NotificationTemplateService(NotificationTemplateRepository templateRepository,
                                       NotificationDeliveryRepository deliveryRepository,
                                       UserRepository userRepository, NotificationDispatcher dispatcher,
                                       PushSender pushSender, WhatsAppSender whatsAppSender) {
        this.templateRepository = templateRepository;
        this.deliveryRepository = deliveryRepository;
        this.userRepository = userRepository;
        this.dispatcher = dispatcher;
        this.pushSender = pushSender;
        this.whatsAppSender = whatsAppSender;
    }

    @Transactional(readOnly = true)
    public CatalogResponse catalog() {
        Map<String, NotificationTemplate> byKey = templateRepository.findAll().stream()
                .collect(Collectors.toMap(NotificationTemplate::getEventKey, Function.identity()));
        List<EventView> events = Arrays.stream(NotificationEvent.values())
                .map(e -> new EventView(e.name(), e.getModule(), e.getLabel(), e.getDescription(),
                        e.getPlaceholders(), e.getDefaultTitle(), e.getDefaultBody(),
                        toView(byKey.get(e.name()))))
                .toList();
        return new CatalogResponse(
                new ChannelStatus(true, pushSender.isConfigured(), whatsAppSender.isConfigured()), events);
    }

    @Transactional
    public TemplateView save(String eventKey, SaveRequest request, UUID adminId) {
        NotificationEvent event = parse(eventKey);
        validate(event, request);

        NotificationTemplate t = templateRepository.findByEventKey(event.name())
                .orElseGet(() -> NotificationTemplate.builder().eventKey(event.name()).build());
        t.setTitleTemplate(request.title().trim());
        t.setBodyTemplate(request.body().trim());
        t.setInAppEnabled(request.inAppEnabled());
        t.setPushEnabled(request.pushEnabled());
        t.setWhatsappEnabled(request.whatsappEnabled());
        String waName = request.whatsappTemplateName();
        t.setWhatsappTemplateName(waName == null || waName.isBlank() ? null : waName.trim());
        t.setEnabled(request.enabled());
        t.setUpdatedBy(adminId);
        t.setUpdatedAt(Instant.now());
        return toView(templateRepository.save(t));
    }

    @Transactional
    public void delete(String eventKey) {
        NotificationEvent event = parse(eventKey);
        templateRepository.findByEventKey(event.name()).ifPresent(templateRepository::delete);
    }

    /** Sends the saved template to the Super Admin themselves, with sample values, over every
     * channel the template has switched on. */
    @Transactional
    public void sendTest(String eventKey, UUID adminId) {
        NotificationEvent event = parse(eventKey);
        NotificationTemplate t = templateRepository.findByEventKey(event.name())
                .orElseThrow(() -> new BadRequestException("Save the template before sending a test"));
        Map<String, String> sample = new HashMap<>();
        for (String p : event.getPlaceholders()) sample.put(p, "<" + p + ">");
        sample.putAll(Map.of("batchName", "Bharatanatyam Beginners", "oldDate", "12 Oct", "newDate", "14 Oct",
                "newTime", "5:30 PM", "date", "12 Oct", "time", "5:30 PM", "reason", "Trainer unavailable."));
        sample.putAll(Map.of("amount", "Rs 2,500", "courseName", "Bharatanatyam", "period", "October 2026",
                "mode", "Cash"));
        dispatcher.fireTest(event, t, adminId, sample);
    }

    @Transactional(readOnly = true)
    public List<DeliveryView> recentDeliveries(int limit) {
        List<NotificationDelivery> rows = deliveryRepository
                .findAllByOrderByCreatedAtDesc(PageRequest.of(0, Math.max(1, Math.min(limit, 200))));
        Map<UUID, String> names = userRepository
                .findAllById(rows.stream().map(NotificationDelivery::getUserId).collect(Collectors.toSet()))
                .stream().collect(Collectors.toMap(User::getId, User::getFullName));
        return rows.stream()
                .map(d -> new DeliveryView(d.getId(), names.getOrDefault(d.getUserId(), "Unknown user"),
                        d.getEventKey(), d.getChannel(), d.getStatus(), d.getDetail(), d.getCreatedAt()))
                .toList();
    }

    private void validate(NotificationEvent event, SaveRequest r) {
        List<String> unknown = TemplateRenderer.unknownPlaceholders(r.title() + " " + r.body(), event.getPlaceholders());
        if (!unknown.isEmpty()) {
            throw new BadRequestException("Unknown placeholder(s) for " + event.getLabel() + ": "
                    + unknown.stream().map(n -> "{{" + n + "}}").collect(Collectors.joining(", "))
                    + ". Allowed: " + event.getPlaceholders().stream().map(n -> "{{" + n + "}}")
                    .collect(Collectors.joining(", ")));
        }
        if (r.whatsappEnabled() && (r.whatsappTemplateName() == null || r.whatsappTemplateName().isBlank())) {
            throw new BadRequestException("WhatsApp needs the name of a template approved in Meta Business Manager");
        }
        if (!r.inAppEnabled() && !r.pushEnabled() && !r.whatsappEnabled() && r.enabled()) {
            throw new BadRequestException("Turn on at least one channel, or disable the template");
        }
    }

    private NotificationEvent parse(String eventKey) {
        try {
            return NotificationEvent.valueOf(eventKey);
        } catch (IllegalArgumentException e) {
            throw new ResourceNotFoundException("Unknown notification event: " + eventKey);
        }
    }

    private TemplateView toView(NotificationTemplate t) {
        if (t == null) return null;
        return new TemplateView(t.getTitleTemplate(), t.getBodyTemplate(), t.isInAppEnabled(), t.isPushEnabled(),
                t.isWhatsappEnabled(), t.getWhatsappTemplateName(), t.isEnabled(), t.getUpdatedAt());
    }
}
