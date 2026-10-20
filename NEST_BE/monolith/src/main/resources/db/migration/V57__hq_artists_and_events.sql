-- HQ Artist verification: the review an HQ person does before a Guest may post as an Artist, and
-- the moderation that follows (reports, three chances, suspension).
--
-- artist_applications stays the request/decision record (V16). It gains what the review needs:
-- the details the applicant gave, the profiles HQ checked, the checklist, and the access granted.
-- Approval still flips users.role_type to ARTIST and suspension flips it back to GUEST, so the
-- rest of the app needs no change.
ALTER TABLE artist_applications ADD COLUMN seq         BIGINT GENERATED ALWAYS AS IDENTITY;
ALTER TABLE artist_applications ADD COLUMN art_form    VARCHAR(80);
ALTER TABLE artist_applications ADD COLUMN city        VARCHAR(80);
ALTER TABLE artist_applications ADD COLUMN bio         VARCHAR(500);
-- [{"pl":"instagram","h":"@handle","f":"48.2K","s":"pending|ok|bad","m":"Code in bio","note":""}]
ALTER TABLE artist_applications ADD COLUMN profiles    TEXT    NOT NULL DEFAULT '[]';
-- {"name":true,"own":true,...} - the review checklist
ALTER TABLE artist_applications ADD COLUMN checklist   TEXT    NOT NULL DEFAULT '{}';
ALTER TABLE artist_applications ADD COLUMN guardian_ok BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE artist_applications ADD COLUMN can_post    BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE artist_applications ADD COLUMN can_events  BOOLEAN NOT NULL DEFAULT FALSE;
-- Upheld reports so far. The third rejects the artist for good.
ALTER TABLE artist_applications ADD COLUMN strikes     SMALLINT NOT NULL DEFAULT 0;
-- What the artist could do before a suspension, restored on reinstatement.
ALTER TABLE artist_applications ADD COLUMN prev_post   BOOLEAN;
ALTER TABLE artist_applications ADD COLUMN prev_events BOOLEAN;
ALTER TABLE artist_applications ADD COLUMN note        VARCHAR(300);

CREATE TABLE hq_artist_reports (
    id             UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    seq            BIGINT        GENERATED ALWAYS AS IDENTITY,
    application_id UUID          NOT NULL REFERENCES artist_applications (id) ON DELETE CASCADE,
    reported_by    VARCHAR(120)  NOT NULL,
    reporter_role  VARCHAR(30)   NOT NULL,
    category       VARCHAR(60)   NOT NULL,
    details        VARCHAR(600)  NOT NULL,
    status         VARCHAR(10)   NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'upheld', 'dismissed')),
    decision_note  VARCHAR(300),
    created_at     TIMESTAMPTZ   NOT NULL DEFAULT now()
);
CREATE INDEX idx_hq_artist_reports_app ON hq_artist_reports (application_id);

CREATE TABLE hq_artist_log (
    id             UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    application_id UUID          NOT NULL REFERENCES artist_applications (id) ON DELETE CASCADE,
    actor_name     VARCHAR(120)  NOT NULL,
    text           VARCHAR(400)  NOT NULL,
    at             TIMESTAMPTZ   NOT NULL DEFAULT now()
);
CREATE INDEX idx_hq_artist_log_app ON hq_artist_log (application_id, at);

-- HQ actions on an academy's event (pause, resume, cancel) with the reason.
CREATE TABLE hq_event_log (
    id         UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id   UUID          NOT NULL REFERENCES events (id) ON DELETE CASCADE,
    kind       VARCHAR(10)   NOT NULL CHECK (kind IN ('HOLD', 'RESUME', 'CANCEL')),
    actor_name VARCHAR(120)  NOT NULL,
    text       VARCHAR(300)  NOT NULL,
    at         TIMESTAMPTZ   NOT NULL DEFAULT now()
);
CREATE INDEX idx_hq_event_log_event ON hq_event_log (event_id, at);
