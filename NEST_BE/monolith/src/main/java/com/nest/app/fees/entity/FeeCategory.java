package com.nest.app.fees.entity;

/**
 * Which side of the fees module a ledger row belongs to.
 *
 * <p>Both categories share one ledger table rather than two: the statement and all-transactions
 * screens read them together, and a UNION of two tables would be paid for on every such read.</p>
 */
public enum FeeCategory {

    /** The recurring course fee, keyed by course and billing period. */
    REGULAR,

    /** A costume/exam/one-off charge, keyed by fee type or by a per-student custom fee. */
    OTHER
}
