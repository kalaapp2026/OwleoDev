-- HQ Console, second pass: notification templates and the monthly invoicing run.

-- ---------------------------------------------------------------------------------------------
-- Notification templates the Super Admin designs and links to a module. The module/event catalogue
-- (and the details each module can put in a message) lives in code, like NotificationEvent; this table
-- holds the wording, channels and audience. It is a design store: the older notification_templates
-- table (V42) is what the four events that fire today actually read.
-- ---------------------------------------------------------------------------------------------
CREATE TABLE hq_notification_templates (
    id          UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    module      VARCHAR(20)   NOT NULL,
    event       VARCHAR(20)   NOT NULL,
    name        VARCHAR(40)   NOT NULL,
    -- student, parent, trainer, admin, all, or self (security messages go to whoever asked).
    audience    VARCHAR(10)   NOT NULL DEFAULT 'student',
    enabled     BOOLEAN       NOT NULL DEFAULT FALSE,
    ch_inapp    BOOLEAN       NOT NULL DEFAULT TRUE,
    ch_push     BOOLEAN       NOT NULL DEFAULT FALSE,
    ch_wa       BOOLEAN       NOT NULL DEFAULT FALSE,
    ch_mail     BOOLEAN       NOT NULL DEFAULT FALSE,
    title       VARCHAR(60)   NOT NULL DEFAULT '',
    body        VARCHAR(240)  NOT NULL DEFAULT '',
    -- Days, minutes, hours or a percentage, depending on the event; 0 when the event has no timing.
    timing      INTEGER       NOT NULL DEFAULT 0 CHECK (timing >= 0),
    -- Security messages only: comma-separated user types that can get it. NULL means every type.
    user_types  VARCHAR(80),
    -- Also message the parent or guardian on WhatsApp.
    par_on      BOOLEAN       NOT NULL DEFAULT FALSE,
    par_minors  BOOLEAN       NOT NULL DEFAULT TRUE,
    par_diff    BOOLEAN       NOT NULL DEFAULT FALSE,
    par_title   VARCHAR(60)   NOT NULL DEFAULT '',
    par_body    VARCHAR(240)  NOT NULL DEFAULT '',
    created_at  TIMESTAMPTZ   NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ   NOT NULL DEFAULT now()
);
CREATE INDEX idx_hq_notification_templates_module ON hq_notification_templates (module, event);

-- ---------------------------------------------------------------------------------------------
-- Invoicing: the monthly bill run to academy admins.
-- ---------------------------------------------------------------------------------------------

-- When bills are made and sent: a single row.
CREATE TABLE hq_invoice_settings (
    id          SMALLINT     PRIMARY KEY DEFAULT 1 CHECK (id = 1),
    auto        BOOLEAN      NOT NULL DEFAULT TRUE,
    gen_day     SMALLINT     NOT NULL DEFAULT 1 CHECK (gen_day BETWEEN 1 AND 28),
    -- same: send the day it is generated. after: send_after days later. day: on send_day of the month.
    send_mode   VARCHAR(5)   NOT NULL DEFAULT 'same' CHECK (send_mode IN ('same', 'after', 'day')),
    send_after  SMALLINT     NOT NULL DEFAULT 2 CHECK (send_after BETWEEN 1 AND 28),
    send_day    SMALLINT     NOT NULL DEFAULT 5 CHECK (send_day BETWEEN 1 AND 28),
    due_days    SMALLINT     NOT NULL DEFAULT 14 CHECK (due_days BETWEEN 1 AND 60),
    ch_mail     BOOLEAN      NOT NULL DEFAULT TRUE,
    ch_app      BOOLEAN      NOT NULL DEFAULT TRUE,
    ch_wa       BOOLEAN      NOT NULL DEFAULT FALSE
);
INSERT INTO hq_invoice_settings (id) VALUES (1);

-- What is waiting for each academy on the next run: the charges the owner changed, a discount, a note,
-- or "skip this month". lines is NULL when the bill is simply the standard one.
CREATE TABLE hq_invoice_drafts (
    academy_id   UUID          PRIMARY KEY REFERENCES academies (id) ON DELETE CASCADE,
    skip         BOOLEAN       NOT NULL DEFAULT FALSE,
    -- [{"label": "...", "amount": 1499, "kind": "PLAN|ADDON|CUSTOM", "standard": 1499}]
    lines        TEXT,
    keep_lines   BOOLEAN       NOT NULL DEFAULT FALSE,
    disc_type    VARCHAR(5)    NOT NULL DEFAULT 'none' CHECK (disc_type IN ('none', 'offer', 'pct', 'flat')),
    offer_id     UUID,
    disc_value   NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (disc_value >= 0),
    disc_reason  VARCHAR(40)   NOT NULL DEFAULT '',
    -- How many more bills the discount applies to, this one included.
    disc_months  SMALLINT      NOT NULL DEFAULT 1 CHECK (disc_months BETWEEN 1 AND 12),
    note         VARCHAR(140)  NOT NULL DEFAULT '',
    updated_at   TIMESTAMPTZ   NOT NULL DEFAULT now()
);

-- One row per monthly run, so History can say how it started and who ran it.
CREATE TABLE hq_invoice_runs (
    period      VARCHAR(7)   PRIMARY KEY,
    run_at      TIMESTAMPTZ  NOT NULL DEFAULT now(),
    run_by      UUID,
    mode        VARCHAR(10)  NOT NULL CHECK (mode IN ('Automatic', 'By hand'))
);

-- Whether and how a bill reached the academy's admins. Bills raised before this migration count as sent.
ALTER TABLE academy_invoices ADD COLUMN sent_at       TIMESTAMPTZ;
ALTER TABLE academy_invoices ADD COLUMN sent_via      VARCHAR(80);
ALTER TABLE academy_invoices ADD COLUMN sent_skipped  VARCHAR(80);
UPDATE academy_invoices SET sent_at = created_at, sent_via = 'Earlier bill' WHERE sent_at IS NULL;
