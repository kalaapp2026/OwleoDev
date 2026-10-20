package com.nest.app.identity.entity;

public enum ArtistApplicationStatus {
    PENDING,
    APPROVED,
    REJECTED,
    /** HQ asked the applicant for more before deciding. */
    INFO,
    /** Approved earlier, access paused after an upheld report. */
    SUSPENDED,
    /** Rejected for good after a third upheld report: cannot apply again. */
    BANNED
}
