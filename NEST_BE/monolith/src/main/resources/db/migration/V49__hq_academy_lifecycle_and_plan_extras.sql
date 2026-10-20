-- HQ console: where an academy is in its life with Owleo, richer contact details, and the extra
-- fields a billing plan needs to be shown and edited as a product.

-- Lifecycle. These three columns are all the HQ needs to place an academy:
--   closed_at set                         -> closed (the prototype's "churned")
--   status = 'SUSPENDED'                  -> suspended by HQ
--   demo_ends_on set                      -> still on its free demo
--   otherwise                             -> live (or "payment due" if it has an overdue bill)
-- go_live_on is the day the demo ended and billing started, kept for the setup-fee month.
ALTER TABLE academies ADD COLUMN demo_ends_on DATE;
ALTER TABLE academies ADD COLUMN go_live_on   DATE;
ALTER TABLE academies ADD COLUMN closed_at    TIMESTAMPTZ;

-- The onboarding form collects more address and owner detail than the original academy row held.
ALTER TABLE academies ADD COLUMN address_line2 VARCHAR(200);
ALTER TABLE academies ADD COLUMN landmark      VARCHAR(120);
ALTER TABLE academies ADD COLUMN district      VARCHAR(80);
ALTER TABLE academies ADD COLUMN country       VARCHAR(60) NOT NULL DEFAULT 'India';
ALTER TABLE academies ADD COLUMN owner_phone   VARCHAR(20);
ALTER TABLE academies ADD COLUMN owner_email   VARCHAR(255);

-- Existing academies were onboarded before demos existed: they are live, and a live academy's
-- go-live day is the day it was created.
UPDATE academies SET go_live_on = created_at::date WHERE go_live_on IS NULL;

-- Plans as products: a colour for the cards, a "most popular" flag, and which optional modules
-- the plan includes (comma list: events, services, study, branding, priority, manager).
ALTER TABLE billing_plans ADD COLUMN tone       VARCHAR(20) NOT NULL DEFAULT 'blue';
ALTER TABLE billing_plans ADD COLUMN popular    BOOLEAN     NOT NULL DEFAULT FALSE;
ALTER TABLE billing_plans ADD COLUMN modules    VARCHAR(200) NOT NULL DEFAULT '';
UPDATE billing_plans SET tone = 'mute'   WHERE code = 'FREE';
UPDATE billing_plans SET tone = 'blue'   WHERE code = 'BASIC';
UPDATE billing_plans SET tone = 'gold',   popular = TRUE, modules = 'events,study,priority' WHERE code = 'STANDARD';
UPDATE billing_plans SET tone = 'violet', modules = 'events,services,study,branding,priority,manager' WHERE code = 'PREMIUM';

CREATE INDEX idx_academies_closed ON academies (closed_at);
CREATE INDEX idx_academies_demo ON academies (demo_ends_on);
