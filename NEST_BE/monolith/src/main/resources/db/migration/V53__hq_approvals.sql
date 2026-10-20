-- HQ Approvals: the requests that need an HQ decision, and the standard flow each kind follows.
--
-- Requests an ACADEMY raises (a plan change, an ownership transfer, closing the academy) already
-- live in academy_requests (V47) and the academy app reads them. hq_requests is HQ's own working
-- record of each: which stage it is at, how long it has waited, and who said what. Requests HQ
-- raises itself (activating an academy after its demo, an exit) exist only here. Each hq_request
-- from an academy request carries source_id so the academy still sees the final answer.

-- One standard flow per kind of request, applied to every academy.
CREATE TABLE hq_workflows (
    type         VARCHAR(30)  PRIMARY KEY,
    label        VARCHAR(60)  NOT NULL,
    -- Comma list of the roles that approve in turn: 'Super admin' or 'Academy owner,Operations admin'.
    stages       VARCHAR(200) NOT NULL,
    sla_days     INTEGER      NOT NULL CHECK (sla_days BETWEEN 1 AND 10),
    escalate_to  VARCHAR(40)  NOT NULL DEFAULT 'Super admin',
    -- Locked flows are the same for every academy; unlocked ones academies may adjust.
    locked       BOOLEAN      NOT NULL DEFAULT TRUE,
    sort_order   INTEGER      NOT NULL DEFAULT 0
);

INSERT INTO hq_workflows (type, label, stages, sla_days, sort_order) VALUES
    ('BANK_CHANGE',          'Bank account change', 'Super admin',                       2, 1),
    ('OWNERSHIP_TRANSFER',   'Ownership transfer',  'Super admin',                       3, 2),
    ('PLAN_CHANGE',          'Plan change',         'Super admin',                       2, 3),
    ('ACADEMY_CLOSURE',      'Academy closure',     'Super admin',                       5, 4),
    ('CANCEL_SUBSCRIPTION',  'Cancel subscription', 'Super admin',                       3, 5),
    ('ACADEMY_ACTIVATION',   'Academy activation',  'Super admin',                       3, 6),
    ('EXIT',                 'Exit',                'Academy owner,Operations admin',    3, 7);

CREATE TABLE hq_requests (
    id            UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    seq           BIGINT       GENERATED ALWAYS AS IDENTITY,
    type          VARCHAR(30)  NOT NULL REFERENCES hq_workflows (type),
    academy_id    UUID         REFERENCES academies (id) ON DELETE SET NULL,
    -- A name for the card ("Owner of Taal Tarang Academy", "Owleo HQ") rather than a user row: HQ
    -- raises some of these itself, and a prospect has no user yet.
    requested_by  VARCHAR(160) NOT NULL,
    summary       VARCHAR(300) NOT NULL,
    -- Extra lines for the card, as a JSON array of [label, value] pairs.
    details       TEXT         NOT NULL DEFAULT '[]',
    -- What an approval will apply, as JSON: {"plan":"GROWTH"} or {"newEmail":"..."} and so on.
    payload       TEXT         NOT NULL DEFAULT '{}',
    stage         INTEGER      NOT NULL DEFAULT 0,
    stage_since   TIMESTAMPTZ  NOT NULL DEFAULT now(),
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT now(),
    decision      VARCHAR(10)  CHECK (decision IN ('approved', 'rejected', 'returned')),
    decided_at    TIMESTAMPTZ,
    decided_by    UUID,
    -- The academy request this was made from, and the HQ record it drives (a lead, an exit).
    source_id     UUID         UNIQUE REFERENCES academy_requests (id) ON DELETE SET NULL,
    ref_kind      VARCHAR(20),
    ref_id        VARCHAR(60)
);
CREATE INDEX idx_hq_requests_open ON hq_requests (decision, created_at);
CREATE INDEX idx_hq_requests_academy ON hq_requests (academy_id);

CREATE TABLE hq_request_history (
    id          UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    request_id  UUID         NOT NULL REFERENCES hq_requests (id) ON DELETE CASCADE,
    at          TIMESTAMPTZ  NOT NULL DEFAULT now(),
    who         VARCHAR(160) NOT NULL,
    text        VARCHAR(400) NOT NULL
);
CREATE INDEX idx_hq_request_history ON hq_request_history (request_id, at);
