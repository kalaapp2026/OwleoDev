package com.nest.common.audit;

import java.lang.annotation.ElementType;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;

/**
 * Marks a service-layer method whose invocation must be audit-logged, e.g.
 * {@code @Auditable(action = "FEE_ENTRY_RECORDED", entityType = "fee_transaction")}.
 * The method's return value is inspected via reflection for a {@code getId()} accessor to fill
 * in the entity id, best-effort.
 */
@Target(ElementType.METHOD)
@Retention(RetentionPolicy.RUNTIME)
public @interface Auditable {
    String action();

    String entityType();
}
