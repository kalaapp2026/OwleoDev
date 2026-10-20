-- HQ Onboarding: prospective academies on their way from a first conversation to live.
--
-- A LEAD is registered with everything onboarding collects. Starting its demo creates the real
-- academy (so the owner can sign in and try it) and moves the lead to DEMO; going live, once the
-- activation checks pass, moves it to LIVE. The lead row stays as the record of how it got there.
CREATE TABLE hq_leads (
    id             UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    stage          VARCHAR(8)    NOT NULL DEFAULT 'LEAD' CHECK (stage IN ('LEAD', 'DEMO', 'LIVE', 'DROPPED')),
    name           VARCHAR(160)  NOT NULL,
    type           VARCHAR(20)   NOT NULL,
    academy_email  VARCHAR(255)  NOT NULL,
    academy_phone  VARCHAR(20)   NOT NULL,
    address_line1  VARCHAR(200)  NOT NULL,
    address_line2  VARCHAR(200),
    landmark       VARCHAR(120),
    city           VARCHAR(80)   NOT NULL,
    district       VARCHAR(80),
    state          VARCHAR(80)   NOT NULL,
    country        VARCHAR(60)   NOT NULL DEFAULT 'India',
    pin            VARCHAR(10)   NOT NULL,
    owner_name     VARCHAR(120)  NOT NULL,
    owner_phone    VARCHAR(20)   NOT NULL,
    owner_email    VARCHAR(255)  NOT NULL,
    plan_code      VARCHAR(40)   NOT NULL,
    est_students   INTEGER       NOT NULL CHECK (est_students > 0),
    demo_months    SMALLINT      NOT NULL DEFAULT 2 CHECK (demo_months IN (2, 3)),
    -- The bank accounts entered at registration, as a JSON array. Account numbers inside are
    -- encrypted; they are copied into academy_bank_accounts when the demo starts.
    banks          TEXT          NOT NULL DEFAULT '[]',
    academy_id     UUID          REFERENCES academies (id) ON DELETE SET NULL,
    demo_started_on DATE,
    demo_done      BOOLEAN       NOT NULL DEFAULT FALSE,
    -- Activation checks.
    v_details      BOOLEAN       NOT NULL DEFAULT FALSE,
    v_gateway      BOOLEAN       NOT NULL DEFAULT FALSE,
    approval_id    UUID          REFERENCES hq_requests (id) ON DELETE SET NULL,
    approved       BOOLEAN       NOT NULL DEFAULT FALSE,
    live_since     DATE,
    created_at     TIMESTAMPTZ   NOT NULL DEFAULT now()
);
CREATE INDEX idx_hq_leads_stage ON hq_leads (stage);
