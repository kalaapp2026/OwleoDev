package com.nest.app.curriculum.entity;

/**
 * PRD 3.3 course-level category - finer-grained than the academy-level category in
 * academy-service.
 *
 * <p>The vocal/instrumental distinction the earlier vocabulary carried now lives on
 * {@code Course.iconKey} instead (a mic icon vs a guitar icon), which expresses it more precisely
 * than a category ever did while keeping the browse-level grouping to the seven disciplines a
 * parent would actually recognise. See V22 for the data remap.
 */
public enum CourseCategory {
    DANCE,
    MUSIC,
    FINE_ARTS,
    LITERATURE,
    THEATRE,
    FASHION,
    OTHERS
}
