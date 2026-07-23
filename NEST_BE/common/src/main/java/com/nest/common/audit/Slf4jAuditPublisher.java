package com.nest.common.audit;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.slf4j.MDC;
import org.springframework.stereotype.Component;
import org.springframework.core.annotation.Order;

@Component
@Order(Integer.MAX_VALUE)
public class Slf4jAuditPublisher implements AuditPublisher {

    private static final Logger auditLog = LoggerFactory.getLogger("AUDIT");

    @Override
    public void publish(AuditEvent event) {
        MDC.put("actorUserId", String.valueOf(event.actorUserId()));
        MDC.put("actorMembershipId", String.valueOf(event.actorMembershipId()));
        MDC.put("action", event.action());
        MDC.put("entityType", event.entityType());
        MDC.put("entityId", String.valueOf(event.entityId()));
        try {
            auditLog.info("action={} entityType={} entityId={} actorUserId={} actorMembershipId={} service={} detail={}",
                    event.action(), event.entityType(), event.entityId(), event.actorUserId(),
                    event.actorMembershipId(), event.serviceName(), event.detail());
        } finally {
            MDC.clear();
        }
    }
}
