package com.nest.identity.entity;

/**
 * LOGIN and REGISTRATION are used from Phase 1. MEMBERSHIP_CONFIRMATION is the "does this person
 * approve being linked to a second academy" flow (PRD 7.4) - modelled now so Phase 5 doesn't need
 * a schema change, per the PRD's own design principle (Section 7.1).
 */
public enum OtpPurpose {
    LOGIN,
    REGISTRATION,
    MEMBERSHIP_CONFIRMATION
}
