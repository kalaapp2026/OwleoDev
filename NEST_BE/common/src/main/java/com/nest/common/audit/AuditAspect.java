package com.nest.common.audit;

import com.nest.common.security.TenantContext;
import org.aspectj.lang.ProceedingJoinPoint;
import org.aspectj.lang.annotation.Around;
import org.aspectj.lang.annotation.Aspect;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import java.lang.reflect.Method;
import java.time.Instant;
import java.util.UUID;

@Aspect
@Component
public class AuditAspect {

    private final AuditPublisher auditPublisher;
    private final String serviceName;

    public AuditAspect(AuditPublisher auditPublisher, @Value("${spring.application.name:unknown-service}") String serviceName) {
        this.auditPublisher = auditPublisher;
        this.serviceName = serviceName;
    }

    @Around("@annotation(auditable)")
    public Object record(ProceedingJoinPoint joinPoint, Auditable auditable) throws Throwable {
        Object result = joinPoint.proceed();

        UUID actorUserId = null;
        UUID actorMembershipId = null;
        try {
            var principal = TenantContext.get();
            if (principal != null) {
                actorUserId = principal.userId();
                actorMembershipId = principal.activeMembershipId();
            }
        } catch (Exception ignored) {
            // best-effort - never let audit logging break the actual operation
        }

        String entityId = extractId(result);
        auditPublisher.publish(new AuditEvent(Instant.now(), actorUserId, actorMembershipId, auditable.action(),
                auditable.entityType(), entityId, serviceName, joinPoint.getSignature().toShortString()));

        return result;
    }

    private String extractId(Object result) {
        if (result == null) {
            return null;
        }
        try {
            Method getId = result.getClass().getMethod("getId");
            Object id = getId.invoke(result);
            return id == null ? null : id.toString();
        } catch (ReflectiveOperationException ex) {
            return null;
        }
    }
}
