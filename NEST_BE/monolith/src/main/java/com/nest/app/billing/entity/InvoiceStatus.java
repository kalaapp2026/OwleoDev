package com.nest.app.billing.entity;

/**
 * DUE and OVERDUE are the same debt at different ages - OVERDUE is derived from due_on passing,
 * not a separate thing an operator sets. WAIVED exists so writing off a charge is recorded rather
 * than deleted, which keeps the invoice history honest.
 */
public enum InvoiceStatus {
    DUE,
    PAID,
    WAIVED
}
