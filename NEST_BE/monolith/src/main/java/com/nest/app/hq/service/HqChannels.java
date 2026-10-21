package com.nest.app.hq.service;

import com.nest.app.notification.channel.PushSender;
import com.nest.app.notification.channel.WhatsAppSender;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.mail.SimpleMailMessage;
import org.springframework.mail.javamail.JavaMailSender;
import org.springframework.stereotype.Component;

import java.util.LinkedHashMap;
import java.util.Map;

/**
 * Which ways of reaching people actually work on this server, and a plain mail send. Used by the
 * notification templates and the monthly bill run so both can say "not set up" truthfully instead of
 * pretending. In-app always works; push and WhatsApp need their credentials; email needs a real SMTP host
 * (the local default points at a developer's MailHog, which is not something to rely on).
 */
@Component
public class HqChannels {

    private final PushSender push;
    private final WhatsAppSender whatsApp;
    private final JavaMailSender mail;
    private final String mailHost;
    private final String from;

    public HqChannels(PushSender push, WhatsAppSender whatsApp, JavaMailSender mail,
                      @Value("${spring.mail.host:localhost}") String mailHost,
                      @Value("${nest.mail.from:no-reply@owleo.app}") String from) {
        this.push = push;
        this.whatsApp = whatsApp;
        this.mail = mail;
        this.mailHost = mailHost == null ? "" : mailHost.trim();
        this.from = from;
    }

    public boolean mailReady() {
        return !mailHost.isEmpty() && !mailHost.equals("localhost") && !mailHost.equals("127.0.0.1");
    }

    /** Keys: inapp, push, wa, mail. */
    public Map<String, Boolean> ready() {
        Map<String, Boolean> m = new LinkedHashMap<>();
        m.put("inapp", true);
        m.put("push", push.isConfigured());
        m.put("wa", whatsApp.isConfigured());
        m.put("mail", mailReady());
        return m;
    }

    public boolean ready(String channel) {
        return Boolean.TRUE.equals(ready().get(channel));
    }

    /** Sends a plain-text email. Throws if the server refuses it; the caller decides how to report that. */
    public void sendMail(String to, String subject, String text) {
        SimpleMailMessage message = new SimpleMailMessage();
        message.setFrom(from);
        message.setTo(to);
        message.setSubject(subject);
        message.setText(text);
        mail.send(message);
    }
}
