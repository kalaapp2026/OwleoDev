-- Online fee payments through a payment gateway (Razorpay).
--
-- One row per checkout attempt. The row exists BEFORE the student pays: it pins what is being paid
-- (the fee, the amount the server computed, who is paying) so that when the gateway later says
-- "order X was paid" - from the browser or from its webhook, whichever arrives first - there is
-- exactly one thing to settle and no way to settle it for a different amount or a different person.
--
-- The ledger (fee_transactions) is still the source of truth for what is owed. A payment order
-- only becomes a fee_transactions row at the moment the gateway confirms it, and fee_transaction_id
-- records which row, so a confirmation that arrives twice cannot post the money twice.

CREATE TABLE payment_orders (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    academy_id          UUID          NOT NULL,
    membership_id       UUID          NOT NULL,
    -- The user who started the checkout; becomes fee_transactions.recorded_by when it settles.
    user_id             UUID          NOT NULL,

    -- What is being paid: REGULAR uses course_id + period, OTHER uses fee_type_id or student_fee_id.
    category            VARCHAR(20)   NOT NULL,
    course_id           UUID,
    period              VARCHAR(60),
    fee_type_id         UUID,
    student_fee_id      UUID,

    -- Rupees as the ledger holds them. amount_paise is the same figure as the gateway sees it.
    amount              NUMERIC(12,2) NOT NULL,
    amount_paise        BIGINT        NOT NULL,
    currency            VARCHAR(3)    NOT NULL DEFAULT 'INR',

    provider            VARCHAR(20)   NOT NULL DEFAULT 'RAZORPAY',
    provider_order_id   VARCHAR(60)   NOT NULL,
    provider_payment_id VARCHAR(60),

    -- CREATED -> PAID. FAILED is set only when the gateway reports a failed payment; the order stays
    -- payable afterwards, so a later successful attempt on the same order still settles it.
    status              VARCHAR(20)   NOT NULL DEFAULT 'CREATED',
    fee_transaction_id  UUID REFERENCES fee_transactions (id),

    created_at          TIMESTAMPTZ   NOT NULL DEFAULT now(),
    paid_at             TIMESTAMPTZ
);

CREATE UNIQUE INDEX uq_payment_orders_provider_order ON payment_orders (provider, provider_order_id);
CREATE INDEX idx_payment_orders_membership ON payment_orders (membership_id, created_at DESC);
-- A gateway payment id settles at most one order.
CREATE UNIQUE INDEX uq_payment_orders_provider_payment ON payment_orders (provider, provider_payment_id)
    WHERE provider_payment_id IS NOT NULL;
