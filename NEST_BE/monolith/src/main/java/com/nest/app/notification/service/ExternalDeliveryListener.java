package com.nest.app.notification.service;

import com.nest.app.identity.repository.UserRepository;
import com.nest.app.notification.channel.ChannelResult;
import com.nest.app.notification.channel.PushSender;
import com.nest.app.notification.channel.WhatsAppSender;
import com.nest.app.notification.entity.DeliveryStatus;
import com.nest.app.notification.entity.NotificationChannel;
import com.nest.app.notification.entity.NotificationDelivery;
import com.nest.app.notification.entity.PushDeviceToken;
import com.nest.app.notification.repository.NotificationDeliveryRepository;
import com.nest.app.notification.repository.PushDeviceTokenRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Async;
import org.springframework.stereotype.Component;
import org.springframework.transaction.event.TransactionPhase;
import org.springframework.transaction.event.TransactionalEventListener;

import java.util.List;
import java.util.Map;
import java.util.UUID;

/** Sends the push / WhatsApp copies off the request thread, after the triggering transaction
 * committed, and records what happened to each. */
@Component
public class ExternalDeliveryListener {

    private static final Logger log = LoggerFactory.getLogger(ExternalDeliveryListener.class);

    private final PushSender pushSender;
    private final WhatsAppSender whatsAppSender;
    private final PushDeviceTokenRepository tokenRepository;
    private final NotificationDeliveryRepository deliveryRepository;
    private final UserRepository userRepository;

    public ExternalDeliveryListener(PushSender pushSender, WhatsAppSender whatsAppSender,
                                    PushDeviceTokenRepository tokenRepository,
                                    NotificationDeliveryRepository deliveryRepository,
                                    UserRepository userRepository) {
        this.pushSender = pushSender;
        this.whatsAppSender = whatsAppSender;
        this.tokenRepository = tokenRepository;
        this.deliveryRepository = deliveryRepository;
        this.userRepository = userRepository;
    }

    // fallbackExecution: the Super Admin test send publishes outside any transaction.
    @Async
    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT, fallbackExecution = true)
    public void on(ExternalDeliveryRequested request) {
        for (ExternalDeliveryRequested.Recipient r : request.recipients()) {
            try {
                if (request.push()) push(request, r);
                if (request.whatsapp()) whatsapp(request, r);
            } catch (RuntimeException e) {
                log.error("External delivery to {} failed for {}", r.userId(), request.eventKey(), e);
            }
        }
    }

    private void push(ExternalDeliveryRequested request, ExternalDeliveryRequested.Recipient r) {
        List<PushDeviceToken> tokens = tokenRepository.findByUserId(r.userId());
        if (tokens.isEmpty()) {
            record(r.userId(), request, NotificationChannel.PUSH, ChannelResult.skipped("No registered device"));
            return;
        }
        Map<String, String> data = Map.of("event", request.eventKey());
        for (PushDeviceToken token : tokens) {
            ChannelResult result = pushSender.send(token.getToken(), r.title(), r.body(), data);
            if (result.invalidToken()) tokenRepository.deleteById(token.getId());
            record(r.userId(), request, NotificationChannel.PUSH, result);
        }
    }

    private void whatsapp(ExternalDeliveryRequested request, ExternalDeliveryRequested.Recipient r) {
        String phone = userRepository.findById(r.userId()).map(u -> u.getPhone()).orElse(null);
        ChannelResult result = whatsAppSender.sendTemplate(phone, request.whatsappTemplateName(), r.whatsappParameters());
        record(r.userId(), request, NotificationChannel.WHATSAPP, result);
    }

    private void record(UUID userId, ExternalDeliveryRequested request, NotificationChannel channel, ChannelResult result) {
        deliveryRepository.save(NotificationDelivery.builder()
                .userId(userId).eventKey(request.eventKey()).channel(channel)
                .status(result.status()).detail(result.detail()).build());
        if (result.status() == DeliveryStatus.FAILED) {
            log.warn("{} to {} failed: {}", channel, userId, result.detail());
        }
    }
}
