package com.nest.app.identity.entity;

/**
 * LOGIN and REGISTRATION are used from Phase 1. MEMBERSHIP_CONFIRMATION is the "does this person
 * approve being linked to a second academy" flow (PRD 7.4) - modelled now so Phase 5 doesn't need
 * a schema change, per the PRD's own design principle (Section 7.1). PASSWORD_RESET is the only
 * one delivered by email rather than phone - see {@link OtpVerification#getEmailHash()}.
 */
public enum OtpPurpose {
    LOGIN,
    REGISTRATION,
    MEMBERSHIP_CONFIRMATION,
    PASSWORD_RESET,
    /** Proves the new address is reachable before it replaces the login email. */
    EMAIL_CHANGE,
    /** HQ academy transfer: the current owner and the new owner each confirm the handover. */
    OWNERSHIP_TRANSFER,
    /** HQ: opening the Finance workspace, confirmed with a code sent to the signed-in person. */
    FINANCE_WORKSPACE
}
