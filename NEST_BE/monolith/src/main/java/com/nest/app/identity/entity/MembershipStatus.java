package com.nest.app.identity.entity;

/**
 * PRD 4.4 academy_memberships.status: supports the OTP-confirmation flow in Section 7.4 -
 * a membership starts PENDING_CONFIRMATION when it links an EXISTING user to a new academy,
 * and only becomes ACTIVE once that person approves via OTP.
 */
public enum MembershipStatus {
    PENDING_CONFIRMATION,
    ACTIVE,
    REVOKED
}
