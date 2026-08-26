package com.nest.app.fees.dto;

/**
 * How a student's fee for one period reads on the roster.
 *
 * <p>Always derived from the ledger at read time, never stored. A stored status is a second copy
 * of a truth the transactions already hold, and the two drift the first time a payment is
 * reversed.</p>
 */
public enum PaymentStatus {

    /** Nothing paid, and still within the period. */
    NOT_PAID,

    /** Nothing paid and the billing period has closed - {@link #NOT_PAID} that has run out of road. */
    DUE,

    /** Something paid, but less than the amount due. */
    PARTIAL,

    /** Settled, most recent payment taken by hand (cash or UPI). */
    PAID_MANUAL,

    /** Settled through the payment gateway. */
    PAID_GATEWAY,

    /** The period was explicitly closed - any shortfall is written off, not carried forward. */
    CLOSED
}
