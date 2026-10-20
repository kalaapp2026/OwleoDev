-- Bank accounts an academy is paid out to, and the link between an HQ action and the academy it
-- was about.

-- "Recent changes" on an academy's profile is the audit trail filtered to that academy.
ALTER TABLE hq_audit_log ADD COLUMN academy_id UUID;
CREATE INDEX idx_hq_audit_academy ON hq_audit_log (academy_id, occurred_at DESC);

-- Up to two accounts per academy, each mapped to one payment gateway. The full account number is
-- encrypted with the same AES-GCM key as other PII and is never returned to the console; the
-- console only ever sees the last four digits.
CREATE TABLE academy_bank_accounts (
    id            UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    academy_id    UUID         NOT NULL REFERENCES academies (id) ON DELETE CASCADE,
    bank          VARCHAR(60)  NOT NULL,
    account_type  VARCHAR(10)  NOT NULL DEFAULT 'Current',
    holder        VARCHAR(120) NOT NULL,
    account_last4 VARCHAR(4)   NOT NULL,
    account_enc   VARCHAR(400) NOT NULL,
    ifsc          VARCHAR(11)  NOT NULL,
    is_primary    BOOLEAN      NOT NULL DEFAULT FALSE,
    -- Razorpay, Cashfree or PayU, and the merchant id HQ got from that gateway; both NULL until mapped.
    gateway       VARCHAR(20),
    merchant_id   VARCHAR(40),
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT now()
);
CREATE INDEX idx_bank_accounts_academy ON academy_bank_accounts (academy_id);
-- At most one primary per academy.
CREATE UNIQUE INDEX uq_bank_primary ON academy_bank_accounts (academy_id) WHERE is_primary;
