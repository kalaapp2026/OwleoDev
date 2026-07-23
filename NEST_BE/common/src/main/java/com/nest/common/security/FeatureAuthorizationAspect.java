package com.nest.common.security;

import com.nest.common.exception.ForbiddenException;
import org.aspectj.lang.ProceedingJoinPoint;
import org.aspectj.lang.annotation.Around;
import org.aspectj.lang.annotation.Aspect;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;

import java.util.Arrays;

/**
 * Enforces {@link RequiresFeature} on controller/service methods by intersecting the annotation's
 * required feature key(s) against the caller's ACTIVE membership feature grants (PRD 2.3, worked
 * example: Arjun only sees Attendance/Schedule tiles because that's what was checked ON for him).
 *
 * <p>Super Admin bypasses this check entirely - they are not scoped to any single academy
 * (PRD 2.4) and therefore never carry feature_grants themselves.
 */
@Aspect
@Component
@Order(10)
public class FeatureAuthorizationAspect {

    @Around("@annotation(requiresFeature)")
    public Object enforce(ProceedingJoinPoint joinPoint, RequiresFeature requiresFeature) throws Throwable {
        NestPrincipal principal = TenantContext.require();
        boolean isAcademyAdmin = principal.activeMembership().map(m -> m.roleType() == Role.ACADEMY_ADMIN).orElse(false);

        // Super Admin is platform-global (PRD 2.4); an Academy Admin has unconditional full ERP
        // access within their own academy by role alone (PRD 2.2) - feature_grants only gate
        // Trainers (PRD 2.3). Neither needs an explicit feature_grants row to pass this check.
        if (!principal.isSuperAdmin() && !isAcademyAdmin) {
            boolean satisfied = requiresFeature.requireAll()
                    ? Arrays.stream(requiresFeature.value()).allMatch(principal::hasFeature)
                    : Arrays.stream(requiresFeature.value()).anyMatch(principal::hasFeature);

            if (!satisfied) {
                throw new ForbiddenException(
                        "Active membership lacks required feature grant(s): " + Arrays.toString(requiresFeature.value()));
            }
        }

        return joinPoint.proceed();
    }
}
