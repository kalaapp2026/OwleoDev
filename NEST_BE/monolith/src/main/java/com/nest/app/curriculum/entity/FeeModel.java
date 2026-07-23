package com.nest.app.curriculum.entity;

/** NEST Course Fee Calculation Spec §2 - how a course's fee is calculated from attendance.
 * PER_CLASS and HYBRID use {@link Course#getFeePerClass()}/hybrid_* fields respectively;
 * FIXED (and HYBRID's full-fee amount) use {@link Course#getDefaultFee()} as the base fee. */
public enum FeeModel {
    PER_CLASS,
    FIXED,
    HYBRID
}
