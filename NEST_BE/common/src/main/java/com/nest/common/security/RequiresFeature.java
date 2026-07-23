package com.nest.common.security;

import java.lang.annotation.ElementType;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;

/**
 * Declares the feature-grant(s) required for the currently active membership to call this
 * endpoint (PRD Section 2.3 / 4.3, e.g. {@code @RequiresFeature(FeatureKey.ATTENDANCE)}).
 *
 * <p>This only checks the feature map. Course-scoping (is this batch/course in the caller's
 * course_map?) is intentionally NOT generalised here - call {@link TenantContext#assertCourseAccess}
 * explicitly once the target course/batch id is resolved, since which request parameter holds
 * that id varies per endpoint.
 */
@Target(ElementType.METHOD)
@Retention(RetentionPolicy.RUNTIME)
public @interface RequiresFeature {

    String[] value();

    /** If true, caller must hold ALL listed features. Default is ANY-of semantics. */
    boolean requireAll() default false;
}
