package com.nest.app.audit;

import com.nest.common.audit.AuditEvent;
import com.nest.common.audit.AuditPublisher;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.context.annotation.Primary;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;

/**
 * Persists every {@code @Auditable} event to the audit_log table (still logs to the AUDIT
 * SLF4J logger too, for console visibility during dev). Marked {@link Primary} so
 * {@code common}'s AuditAspect picks this over the log-only {@code Slf4jAuditPublisher} default
 * whenever both are on the classpath.
 *
 * <p>REQUIRES_NEW so an audit write is never rolled back by the very transaction it's recording -
 * and, conversely, a failed audit write never takes down the business operation it's auditing.
 */
@Component
@Primary
public class JpaAuditPublisher implements AuditPublisher {

    private static final Logger log = LoggerFactory.getLogger("AUDIT");

    private final AuditLogRepository repository;

    public JpaAuditPublisher(AuditLogRepository repository) {
        this.repository = repository;
    }

    @Override
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void publish(AuditEvent event) {
        try {
            repository.save(AuditLog.builder()
                    .occurredAt(event.timestamp())
                    .actorUserId(event.actorUserId())
                    .actorMembershipId(event.actorMembershipId())
                    .action(event.action())
                    .entityType(event.entityType())
                    .entityId(event.entityId())
                    .source(event.serviceName())
                    .detail(event.detail())
                    .createdAt(Instant.now())
                    .build());
        } catch (Exception ex) {
            // Never let a broken audit write break the operation it's auditing.
            log.error("Failed to persist audit_log row for action={} entityType={}", event.action(), event.entityType(), ex);
        }
        log.info("action={} entityType={} entityId={} actorUserId={} actorMembershipId={}",
                event.action(), event.entityType(), event.entityId(), event.actorUserId(), event.actorMembershipId());
    }
}
