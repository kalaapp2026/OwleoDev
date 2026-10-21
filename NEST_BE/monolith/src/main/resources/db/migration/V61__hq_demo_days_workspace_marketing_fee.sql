-- HQ console, second round.

-- 1. A demo can run from 15 days to 3 months, in whole days. Existing leads keep the length they had.
ALTER TABLE hq_leads ADD COLUMN demo_days SMALLINT;
UPDATE hq_leads SET demo_days = demo_months * 30;
ALTER TABLE hq_leads ALTER COLUMN demo_days SET NOT NULL;
ALTER TABLE hq_leads ALTER COLUMN demo_days SET DEFAULT 60;
ALTER TABLE hq_leads ADD CONSTRAINT ck_hq_leads_demo_days CHECK (demo_days BETWEEN 15 AND 90);
ALTER TABLE hq_leads DROP COLUMN demo_months;

-- 2. Marketing fees are a revenue line of their own (what an academy pays Owleo for promotion).
ALTER TABLE invoice_lines DROP CONSTRAINT invoice_lines_kind_check;
ALTER TABLE invoice_lines ADD CONSTRAINT invoice_lines_kind_check
    CHECK (kind IN ('PLAN', 'ADDON', 'COMMISSION', 'SETUP', 'ADJUSTMENT', 'MARKETING'));

-- 3. Finance is a separate workspace. Opening it takes a code sent to the person's email, and the
--    grant lasts until they close it or it expires. Finance data is refused without a live grant.
CREATE TABLE hq_workspace_grants (
    user_id    UUID         PRIMARY KEY REFERENCES users (id) ON DELETE CASCADE,
    opened_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
    expires_at TIMESTAMPTZ  NOT NULL
);
