-- HQ Collections and Finance: what academy owners pay Owleo (plan, add-ons, event commission,
-- setup), in enough detail to bill it, chase it and report it.
--
-- academy_invoices (V18) stays the bill header and stays readable by the older billing screens.
-- What it could not express is moved into child tables: the line items, several part-payments
-- against one bill, the reminders sent, and the GST/discount arithmetic.

ALTER TABLE academy_invoices ADD COLUMN discount  NUMERIC(12,2) NOT NULL DEFAULT 0;
ALTER TABLE academy_invoices ADD COLUMN gst       NUMERIC(12,2) NOT NULL DEFAULT 0;
-- total = sum(lines) + adjustments - discount + gst, kept on the row so lists can sort and sum
-- without re-deriving it. For bills raised before this migration it equals `amount` (no GST was
-- ever charged on them, and rewriting what an academy was already billed would be wrong).
ALTER TABLE academy_invoices ADD COLUMN total     NUMERIC(12,2);
ALTER TABLE academy_invoices ADD COLUMN offer_id  UUID;
UPDATE academy_invoices SET total = amount WHERE total IS NULL;
ALTER TABLE academy_invoices ALTER COLUMN total SET NOT NULL;

-- kind: PLAN (the subscription), ADDON, COMMISSION (events), SETUP (one-time onboarding),
-- ADJUSTMENT (a manual charge, or a negative credit).
CREATE TABLE invoice_lines (
    id          UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    invoice_id  UUID          NOT NULL REFERENCES academy_invoices (id) ON DELETE CASCADE,
    kind        VARCHAR(12)   NOT NULL CHECK (kind IN ('PLAN', 'ADDON', 'COMMISSION', 'SETUP', 'ADJUSTMENT')),
    label       VARCHAR(160)  NOT NULL,
    amount      NUMERIC(12,2) NOT NULL,
    created_at  TIMESTAMPTZ   NOT NULL DEFAULT now()
);
CREATE INDEX idx_invoice_lines_invoice ON invoice_lines (invoice_id);

-- Every bill so far was a single subscription charge.
INSERT INTO invoice_lines (invoice_id, kind, label, amount)
SELECT i.id, 'PLAN', COALESCE(p.display_name, i.plan_code) || ' plan', i.amount
FROM academy_invoices i LEFT JOIN billing_plans p ON p.code = i.plan_code;

-- Several payments can settle one bill (a part-payment, then the rest).
CREATE TABLE invoice_payments (
    id          UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    invoice_id  UUID          NOT NULL REFERENCES academy_invoices (id) ON DELETE CASCADE,
    paid_on     DATE          NOT NULL,
    amount      NUMERIC(12,2) NOT NULL CHECK (amount > 0),
    mode        VARCHAR(30)   NOT NULL,
    reference   VARCHAR(120),
    recorded_by UUID,
    created_at  TIMESTAMPTZ   NOT NULL DEFAULT now()
);
CREATE INDEX idx_invoice_payments_invoice ON invoice_payments (invoice_id);
CREATE INDEX idx_invoice_payments_day ON invoice_payments (paid_on);

INSERT INTO invoice_payments (invoice_id, paid_on, amount, mode, reference, recorded_by)
SELECT id, COALESCE(paid_at::date, issued_on), paid_amount, COALESCE(payment_method, 'Bank transfer'), payment_ref, recorded_by
FROM academy_invoices WHERE paid_amount IS NOT NULL AND paid_amount > 0;

CREATE TABLE invoice_reminders (
    id          UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    invoice_id  UUID          NOT NULL REFERENCES academy_invoices (id) ON DELETE CASCADE,
    sent_at     TIMESTAMPTZ   NOT NULL DEFAULT now(),
    channels    VARCHAR(60)   NOT NULL,
    sent_by     UUID,
    message     VARCHAR(600)  NOT NULL
);
CREATE INDEX idx_invoice_reminders_invoice ON invoice_reminders (invoice_id);

-- Promotional offers applied to one bill at a time. type: PCT (percent off), FLAT (rupees off),
-- FREE (the first month's plan charge waived). applies_to is a plan code or 'all'.
CREATE TABLE hq_offers (
    id          UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    name        VARCHAR(120)  NOT NULL,
    code        VARCHAR(14)   NOT NULL UNIQUE,
    type        VARCHAR(8)    NOT NULL CHECK (type IN ('PCT', 'FLAT', 'FREE')),
    value       NUMERIC(12,2) NOT NULL DEFAULT 0,
    applies_to  VARCHAR(40)   NOT NULL DEFAULT 'all',
    starts_on   DATE          NOT NULL,
    ends_on     DATE          NOT NULL,
    use_limit   INTEGER,
    active      BOOLEAN       NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ   NOT NULL DEFAULT now()
);

-- Things an academy can add to its plan for a monthly or one-time charge.
CREATE TABLE hq_addons (
    id          UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    name        VARCHAR(120)  NOT NULL,
    description VARCHAR(240)  NOT NULL,
    price       NUMERIC(12,2) NOT NULL CHECK (price > 0),
    billing     VARCHAR(10)   NOT NULL CHECK (billing IN ('MONTH', 'ONE_TIME')),
    on_sale     BOOLEAN       NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ   NOT NULL DEFAULT now()
);

CREATE TABLE academy_addons (
    academy_id   UUID         NOT NULL REFERENCES academies (id) ON DELETE CASCADE,
    addon_id     UUID         NOT NULL REFERENCES hq_addons (id),
    -- 'YYYY-MM': the first bill it appears on.
    from_period  VARCHAR(7)   NOT NULL,
    PRIMARY KEY (academy_id, addon_id)
);

-- Automatic reminder rules (3 days before, on the day, 3 days after, weekly while overdue) and
-- which channels they use: a single row.
CREATE TABLE hq_reminder_settings (
    id           SMALLINT     PRIMARY KEY DEFAULT 1 CHECK (id = 1),
    before_3d    BOOLEAN      NOT NULL DEFAULT TRUE,
    on_due       BOOLEAN      NOT NULL DEFAULT TRUE,
    after_3d     BOOLEAN      NOT NULL DEFAULT TRUE,
    weekly       BOOLEAN      NOT NULL DEFAULT FALSE,
    ch_whatsapp  BOOLEAN      NOT NULL DEFAULT TRUE,
    ch_email     BOOLEAN      NOT NULL DEFAULT TRUE,
    ch_sms       BOOLEAN      NOT NULL DEFAULT FALSE
);
INSERT INTO hq_reminder_settings (id) VALUES (1);

-- Owleo's own running costs, entered per month and category. This is what turns revenue into
-- profit on the Finance page. category: SALARY, CLOUD, MARKETING, SUPPORT, MESSAGING, MISC.
CREATE TABLE hq_expenses (
    month       VARCHAR(7)    NOT NULL,
    category    VARCHAR(12)   NOT NULL CHECK (category IN ('SALARY', 'CLOUD', 'MARKETING', 'SUPPORT', 'MESSAGING', 'MISC')),
    amount      NUMERIC(12,2) NOT NULL CHECK (amount >= 0),
    updated_by  UUID,
    updated_at  TIMESTAMPTZ   NOT NULL DEFAULT now(),
    PRIMARY KEY (month, category)
);

-- Growth targets the owner tracks progress against (academies, users, MRR, monthly revenue).
CREATE TABLE hq_targets (
    key     VARCHAR(20)   PRIMARY KEY,
    label   VARCHAR(80)   NOT NULL,
    target  NUMERIC(14,2) NOT NULL CHECK (target > 0)
);
INSERT INTO hq_targets (key, label, target) VALUES
    ('academies', '100 academies', 100),
    ('users', '25,000 Owleo users', 25000),
    ('mrr', '₹3L monthly recurring revenue', 300000),
    ('revenue', '₹2L monthly revenue', 200000);

-- Configurable one-off fee charged when an academy goes live.
CREATE TABLE hq_settings (
    key    VARCHAR(40)  PRIMARY KEY,
    value  VARCHAR(200) NOT NULL
);
INSERT INTO hq_settings (key, value) VALUES ('setup_fee', '4999'), ('gst_percent', '18'), ('event_commission_percent', '5');
