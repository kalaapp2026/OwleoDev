package com.nest.app.fees.entity;

/** Whether an underpaid period's shortfall carries forward into the next fee slip (OPEN, the
 * default) or is written off for good ("close" - PRD-style business rule the Admin/Trainer
 * chooses at payment-recording time, e.g. "1000 due, 500 paid, remaining 500 written off"). */
public enum FeeSlipStatus {
    OPEN,
    CLOSED
}
