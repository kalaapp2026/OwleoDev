-- HQ Academy transfer: handing an academy to a new owner, confirmed by BOTH people with a one-time code.
--
-- The request normally starts in the academy app (an OWNERSHIP_TRANSFER request, reached through
-- Approvals). HQ then runs verification here: a code to the current owner's phone, a code to the new
-- owner's email, and the academy moves only after both are entered correctly.
CREATE TABLE hq_transfers (
    id               UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    seq              BIGINT        GENERATED ALWAYS AS IDENTITY,
    academy_id       UUID          NOT NULL REFERENCES academies (id) ON DELETE CASCADE,
    request_id       UUID          REFERENCES hq_requests (id) ON DELETE SET NULL,
    new_name         VARCHAR(120)  NOT NULL,
    new_email        VARCHAR(255)  NOT NULL,
    new_phone        VARCHAR(20),
    reason           VARCHAR(200)  NOT NULL,
    notes            VARCHAR(500),
    step             VARCHAR(8)    NOT NULL DEFAULT 'REVIEW' CHECK (step IN ('REVIEW', 'OTP', 'DONE', 'REJECTED')),
    verified_from    BOOLEAN       NOT NULL DEFAULT FALSE,
    verified_to      BOOLEAN       NOT NULL DEFAULT FALSE,
    sent_from_at     TIMESTAMPTZ,
    sent_to_at       TIMESTAMPTZ,
    previous_owner   VARCHAR(120),
    why              VARCHAR(300),
    done_at          TIMESTAMPTZ,
    created_at       TIMESTAMPTZ   NOT NULL DEFAULT now()
);
CREATE INDEX idx_hq_transfers_step ON hq_transfers (step);
CREATE INDEX idx_hq_transfers_academy ON hq_transfers (academy_id);

CREATE TABLE hq_transfer_history (
    id          UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    transfer_id UUID          NOT NULL REFERENCES hq_transfers (id) ON DELETE CASCADE,
    actor_name  VARCHAR(120)  NOT NULL,
    text        VARCHAR(300)  NOT NULL,
    at          TIMESTAMPTZ   NOT NULL DEFAULT now()
);
CREATE INDEX idx_hq_transfer_history ON hq_transfer_history (transfer_id, at DESC);
