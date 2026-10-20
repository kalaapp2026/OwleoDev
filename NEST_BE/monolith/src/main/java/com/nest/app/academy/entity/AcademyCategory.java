package com.nest.app.academy.entity;

/** PRD 3.2 onboarding fields: category = Dance / Music / Multi-discipline. Distinct from the
 * finer-grained per-course category owned by curriculum-service (PRD 3.3). FINE_ARTS and THEATRE
 * were added for the HQ console's academy types; the column is a plain string, so no data moves. */
public enum AcademyCategory {
    DANCE,
    MUSIC,
    FINE_ARTS,
    THEATRE,
    MULTI_DISCIPLINE
}
