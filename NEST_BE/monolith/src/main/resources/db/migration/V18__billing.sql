-- Platform billing: what each ACADEMY owes NEST for using the platform.
--
-- Deliberately separate from the existing fee_slips / fee_transactions tables, which are an
-- academy billing its own STUDENTS. Same word, opposite direction of money, and conflating them
-- would make both unreadable.

-- What a plan costs. A table rather than an enum so pricing can change without a deploy, and so
-- an academy that signed up on old pricing keeps the amount recorded on its invoices.
CREATE TABLE billing_plans (
    code           VARCHAR(40) PRIMARY KEY,
    display_name   VARCHAR(80)  NOT NULL,
    monthly_price  NUMERIC(12,2) NOT NULL,
    -- Soft caps: shown in the console and used for "this tenant has outgrown its plan" flags.
    -- Enforcement is deliberately NOT wired into student/course creation - silently blocking a
    -- class from being created because of a billing limit is a terrible experience, and the
    -- operator should have the conversation instead.
    max_students   INTEGER,
    max_trainers   INTEGER,
    active         BOOLEAN      NOT NULL DEFAULT TRUE,
    created_at     TIMESTAMPTZ  NOT NULL DEFAULT now()
);

INSERT INTO billing_plans (code, display_name, monthly_price, max_students, max_trainers) VALUES
    ('FREE',     'Free',     0.00,    25,   2),
    ('BASIC',    'Basic',    1499.00, 150,  10),
    ('STANDARD', 'Standard', 2999.00, 500,  40),
    ('PREMIUM',  'Premium',  5999.00, NULL, NULL);

-- One row per academy per billing month.
CREATE TABLE academy_invoices (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    academy_id     UUID          NOT NULL,
    -- 'YYYY-MM'. Unique per academy so re-running generation for a month is idempotent rather
    -- than double-charging - the single most important property of a billing job.
    period         VARCHAR(7)    NOT NULL,
    plan_code      VARCHAR(40)   NOT NULL,
    -- Copied from the plan at issue time, never read live: changing a price must not silently
    -- rewrite what an academy was already invoiced.
    amount         NUMERIC(12,2) NOT NULL,
    status         VARCHAR(20)   NOT NULL DEFAULT 'DUE',
    issued_on      DATE          NOT NULL,
    due_on         DATE          NOT NULL,
    paid_at        TIMESTAMPTZ,
    paid_amount    NUMERIC(12,2),
    payment_method VARCHAR(30),
    payment_ref    VARCHAR(120),
    note           VARCHAR(500),
    recorded_by    UUID,
    created_at     TIMESTAMPTZ   NOT NULL DEFAULT now(),
    CONSTRAINT uq_invoice_academy_period UNIQUE (academy_id, period)
);

CREATE INDEX idx_invoices_academy ON academy_invoices (academy_id);
CREATE INDEX idx_invoices_status ON academy_invoices (status);
CREATE INDEX idx_invoices_due ON academy_invoices (due_on);

-- Existing academies already carry a free-text plan string; keep them consistent with the plan
-- table so nothing starts life pointing at a plan code that doesn't exist.
UPDATE academies SET plan = 'STANDARD'
WHERE plan IS NULL OR plan NOT IN (SELECT code FROM billing_plans);
