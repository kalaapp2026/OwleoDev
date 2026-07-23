package com.nest.common.audit;

/**
 * Sink for {@link AuditEvent}s. The default binding just logs structured JSON
 * ({@link Slf4jAuditPublisher}); a service that wants durable audit rows should additionally
 * persist via its own JPA repository, and/or bind a Kafka-backed implementation once the
 * message broker is wired in a later phase.
 */
public interface AuditPublisher {
    void publish(AuditEvent event);
}
