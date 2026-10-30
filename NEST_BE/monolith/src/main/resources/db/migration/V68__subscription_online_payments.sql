-- An academy admin paying Owleo's monthly bill online (Razorpay), and a plain record of where each payment
-- came from so HQ can show a transaction history.
--
-- One row per checkout attempt, created BEFORE the admin pays so the gateway's later "order X was paid" -
-- from the browser or from the webhook, whichever arrives first - settles exactly one thing, for exactly the
-- amount the server priced. A paid order becomes an invoice_payments row at the moment it is confirmed;
-- invoice_payment_id records which, so a confirmation that arrives twice cannot post the money twice.
CREATE TABLE invoice_payment_orders (
    id                  UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    invoice_id          UUID          NOT NULL REFERENCES academy_invoices (id),
    academy_id          UUID          NOT NULL,
    -- The academy admin who started the checkout.
    user_id             UUID          NOT NULL,
    amount              NUMERIC(12,2) NOT NULL CHECK (amount > 0),
    amount_paise        BIGINT        NOT NULL CHECK (amount_paise > 0),
    currency            VARCHAR(3)    NOT NULL DEFAULT 'INR',
    provider            VARCHAR(20)   NOT NULL DEFAULT 'RAZORPAY',
    provider_order_id   VARCHAR(60)   NOT NULL,
    provider_payment_id VARCHAR(60),
    -- CREATED -> PAID. FAILED only when the gateway reports a failed attempt; the order stays payable after.
    status              VARCHAR(10)   NOT NULL DEFAULT 'CREATED' CHECK (status IN ('CREATED', 'PAID', 'FAILED')),
    -- Why a payment needs a person to look at it (for example: paid after the bill was already settled).
    note                VARCHAR(200),
    invoice_payment_id  UUID,
    created_at          TIMESTAMPTZ   NOT NULL DEFAULT now(),
    paid_at             TIMESTAMPTZ
);
CREATE UNIQUE INDEX uq_invoice_orders_provider_order ON invoice_payment_orders (provider, provider_order_id);
CREATE UNIQUE INDEX uq_invoice_orders_provider_payment ON invoice_payment_orders (provider, provider_payment_id)
    WHERE provider_payment_id IS NOT NULL;
CREATE INDEX idx_invoice_orders_invoice ON invoice_payment_orders (invoice_id, created_at DESC);
CREATE INDEX idx_invoice_orders_academy ON invoice_payment_orders (academy_id, created_at DESC);

-- Where a recorded payment came from: ONLINE (the academy paid through the gateway) or MANUAL (HQ typed it in).
ALTER TABLE invoice_payments ADD COLUMN source VARCHAR(10) NOT NULL DEFAULT 'MANUAL' CHECK (source IN ('ONLINE', 'MANUAL'));
