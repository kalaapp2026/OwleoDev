-- HQ Marketing and Service providers.

-- Marketing: whether a person has agreed to be reached by ads. Only people with TRUE are ever counted as
-- reachable, and under-18s are only ever reached through their guardian. Nobody is consented by default.
ALTER TABLE users ADD COLUMN marketing_consent BOOLEAN NOT NULL DEFAULT FALSE;

-- Campaigns HQ runs on behalf of an academy. Delivery numbers (spend, reach, clicks, leads) are
-- entered from the ad platform, since Owleo does not run the ads itself.
CREATE TABLE hq_campaigns (
    id          UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    name        VARCHAR(120)  NOT NULL,
    academy_id  UUID          NOT NULL REFERENCES academies (id) ON DELETE CASCADE,
    channel     VARCHAR(8)    NOT NULL CHECK (channel IN ('META', 'INAPP', 'BOTH')),
    audience    VARCHAR(6)    NOT NULL CHECK (audience IN ('GUARD', 'ADULT', 'ALL')),
    interests   VARCHAR(200)  NOT NULL DEFAULT '',
    budget      NUMERIC(12,2) NOT NULL CHECK (budget > 0),
    days        SMALLINT      NOT NULL CHECK (days IN (7, 14, 30)),
    status      VARCHAR(8)    NOT NULL DEFAULT 'DRAFT' CHECK (status IN ('DRAFT', 'LIVE', 'PAUSED', 'ENDED')),
    spend       NUMERIC(12,2) NOT NULL DEFAULT 0,
    reach       INTEGER       NOT NULL DEFAULT 0,
    clicks      INTEGER       NOT NULL DEFAULT 0,
    leads       INTEGER       NOT NULL DEFAULT 0,
    starts_on   DATE,
    ends_on     DATE,
    created_at  TIMESTAMPTZ   NOT NULL DEFAULT now()
);
CREATE INDEX idx_hq_campaigns_status ON hq_campaigns (status);

-- Service providers: photographers, stage and decor crews and so on, hired by academies for events.
-- Owleo checks their portfolio links and identity, then makes them live. No media is stored here.
CREATE TABLE hq_provider_types (
    code    VARCHAR(20)  PRIMARY KEY,
    name    VARCHAR(40)  NOT NULL,
    icon    VARCHAR(20)  NOT NULL,
    tone    VARCHAR(12)  NOT NULL,
    active  BOOLEAN      NOT NULL DEFAULT TRUE
);
INSERT INTO hq_provider_types (code, name, icon, tone) VALUES
    ('photo', 'Photography', 'camera', 'blue'), ('video', 'Videography', 'eye', 'violet'), ('stage', 'Stage and lights', 'layers', 'gold'),
    ('sound', 'Sound', 'pulse', 'primary'), ('decor', 'Decor', 'spark', 'magenta'), ('cost', 'Costumes', 'user', 'coral'),
    ('jewel', 'Jewellery', 'star', 'gold'), ('makeup', 'Makeup', 'heart', 'magenta'), ('music', 'Live music', 'mega', 'primary'),
    ('instr', 'Instrument rental', 'book', 'green'), ('set', 'Set design', 'grid', 'violet'), ('props', 'Props', 'file', 'coral'),
    ('emcee', 'Emcee', 'msg', 'blue');

CREATE TABLE hq_providers (
    id          UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    seq         BIGINT        GENERATED ALWAYS AS IDENTITY,
    name        VARCHAR(120)  NOT NULL,
    person      VARCHAR(120)  NOT NULL,
    phone       VARCHAR(20)   NOT NULL,
    email       VARCHAR(255)  NOT NULL,
    city        VARCHAR(80)   NOT NULL,
    types       VARCHAR(200)  NOT NULL,
    status      VARCHAR(10)   NOT NULL DEFAULT 'APPLIED' CHECK (status IN ('APPLIED', 'REVIEW', 'VERIFY', 'LIVE', 'SUSPENDED', 'REJECTED')),
    price       NUMERIC(12,2) NOT NULL CHECK (price >= 0),
    unit        VARCHAR(40)   NOT NULL,
    services    VARCHAR(800)  NOT NULL DEFAULT '',
    bio         VARCHAR(500)  NOT NULL DEFAULT '',
    exp_years   SMALLINT      NOT NULL DEFAULT 0,
    -- [{"u":"https://...","ok":true|false|null}]
    links       TEXT          NOT NULL DEFAULT '[]',
    -- {"id":true,"biz":false,"call":false,"refs":false}
    kyc         TEXT          NOT NULL DEFAULT '{}',
    applied_on  DATE          NOT NULL DEFAULT current_date,
    created_at  TIMESTAMPTZ   NOT NULL DEFAULT now()
);
CREATE INDEX idx_hq_providers_status ON hq_providers (status);

CREATE TABLE hq_provider_log (
    id          UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    provider_id UUID          NOT NULL REFERENCES hq_providers (id) ON DELETE CASCADE,
    actor_name  VARCHAR(120)  NOT NULL,
    text        VARCHAR(400)  NOT NULL,
    at          TIMESTAMPTZ   NOT NULL DEFAULT now()
);
CREATE INDEX idx_hq_provider_log ON hq_provider_log (provider_id, at DESC);

-- An academy's request for a service, passed on by HQ to suitable providers.
CREATE TABLE hq_provider_requests (
    id          UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    seq         BIGINT        GENERATED ALWAYS AS IDENTITY,
    academy_id  UUID          NOT NULL REFERENCES academies (id) ON DELETE CASCADE,
    type_code   VARCHAR(20)   NOT NULL REFERENCES hq_provider_types (code),
    event_name  VARCHAR(120)  NOT NULL,
    event_date  DATE          NOT NULL,
    budget      NUMERIC(12,2) NOT NULL CHECK (budget > 0),
    status      VARCHAR(8)    NOT NULL DEFAULT 'OPEN' CHECK (status IN ('OPEN', 'MATCHED', 'QUOTED', 'HIRED', 'CLOSED')),
    -- [{"p":"<provider id>","amt":14000}]
    quotes      TEXT          NOT NULL DEFAULT '[]',
    hired_id    UUID          REFERENCES hq_providers (id) ON DELETE SET NULL,
    created_at  TIMESTAMPTZ   NOT NULL DEFAULT now()
);
CREATE TABLE hq_provider_request_sent (
    request_id  UUID NOT NULL REFERENCES hq_provider_requests (id) ON DELETE CASCADE,
    provider_id UUID NOT NULL REFERENCES hq_providers (id) ON DELETE CASCADE,
    sent_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (request_id, provider_id)
);

-- A hired job, and how it went: the source of every provider's rating and reliability figures.
CREATE TABLE hq_provider_jobs (
    id          UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    provider_id UUID          NOT NULL REFERENCES hq_providers (id) ON DELETE CASCADE,
    academy_id  UUID          NOT NULL REFERENCES academies (id) ON DELETE CASCADE,
    request_id  UUID          REFERENCES hq_provider_requests (id) ON DELETE SET NULL,
    event_name  VARCHAR(120)  NOT NULL,
    job_date    DATE          NOT NULL,
    amount      NUMERIC(12,2) NOT NULL DEFAULT 0,
    status      VARCHAR(10)   NOT NULL DEFAULT 'UPCOMING' CHECK (status IN ('UPCOMING', 'DONE', 'CANCELLED')),
    rating      SMALLINT      CHECK (rating BETWEEN 1 AND 5),
    late        BOOLEAN       NOT NULL DEFAULT FALSE,
    issue       BOOLEAN       NOT NULL DEFAULT FALSE
);
CREATE INDEX idx_hq_provider_jobs ON hq_provider_jobs (provider_id, job_date DESC);
