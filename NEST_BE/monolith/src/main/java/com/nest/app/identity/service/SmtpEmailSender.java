package com.nest.app.identity.service;

import com.nest.app.identity.entity.OtpPurpose;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.mail.SimpleMailMessage;
import org.springframework.mail.javamail.JavaMailSender;
import org.springframework.stereotype.Component;

/**
 * Real SMTP delivery via Spring Mail. In dev, {@code spring.mail.host}/{@code port} point at the
 * MailHog container from infra/docker-compose.yml (localhost:1025, no auth, no TLS) so a reset
 * code is genuinely sent and viewable at http://localhost:8025 - production sets
 * MAIL_HOST/MAIL_PORT/MAIL_USERNAME/MAIL_PASSWORD to a real provider via env vars.
 */
@Component
public class SmtpEmailSender implements EmailSender {

    private static final Logger log = LoggerFactory.getLogger(SmtpEmailSender.class);

    private final JavaMailSender mailSender;
    private final String fromAddress;

    public SmtpEmailSender(JavaMailSender mailSender, @Value("${nest.mail.from}") String fromAddress) {
        this.mailSender = mailSender;
        this.fromAddress = fromAddress;
    }

    @Override
    public void sendOtp(String rawEmail, String code, OtpPurpose purpose) {
        SimpleMailMessage message = new SimpleMailMessage();
        message.setFrom(fromAddress);
        message.setTo(rawEmail);
        message.setSubject(purpose == OtpPurpose.PASSWORD_RESET
                ? "Reset your Owleo N.E.S.T. password"
                : "Your Owleo N.E.S.T. verification code");
        message.setText("Your code is " + code + ". It expires in 5 minutes.\n\n"
                + "If you didn't request this, you can safely ignore this email.");
        try {
            mailSender.send(message);
        } catch (Exception ex) {
            // The OTP row is already persisted by the time this runs (see OtpService) - a delivery
            // failure shouldn't surface as "your code request failed" when the code itself is
            // perfectly valid; it just means the person needs to hit resend/check spam. Logged loud
            // so a real prod misconfiguration (bad SMTP creds) doesn't go unnoticed.
            log.error("Failed to send {} email OTP to an address ending in '{}'", purpose,
                    rawEmail.length() > 4 ? rawEmail.substring(rawEmail.length() - 4) : rawEmail, ex);
        }
    }
}
