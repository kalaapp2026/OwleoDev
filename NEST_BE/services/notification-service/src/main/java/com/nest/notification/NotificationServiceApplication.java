package com.nest.notification;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/**
 * STUB - reactor placeholder only. Kafka consumer dispatching push/WhatsApp/SMS from templates (Phase 4).
 * No datasource/JPA/Flyway wired yet on purpose: this module exists so the Maven reactor and
 * the gateway route table are complete from day one, without requiring a live Postgres DB for
 * every one of the 11 services before Phase 1 can even build. Real entities/endpoints land in
 * the phase noted above.
 */
@SpringBootApplication
public class NotificationServiceApplication {
    public static void main(String[] args) {
        SpringApplication.run(NotificationServiceApplication.class, args);
    }
}
