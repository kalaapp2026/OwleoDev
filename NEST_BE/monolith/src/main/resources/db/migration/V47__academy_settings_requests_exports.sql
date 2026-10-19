-- Academy Settings: the academy's default communication language, the requests an Academy Admin
-- raises with the platform team (things only Owleo can carry out), and a log of data exports.

-- Language used for receipts, reminders and broadcasts to students - separate from any one
-- person's own display language. Stored now; existing academies default to English.
ALTER TABLE academies ADD COLUMN default_language VARCHAR(10) NOT NULL DEFAULT 'en';

-- A request from an academy to the Super Admin team. Ownership transfer, a plan change, ending a
-- subscription and closing the academy are all things the academy cannot do for itself, so they
-- are asked for here and answered (approved or declined) by the platform. SUPPORT is a plain
-- message to the team. Only the columns a given type needs are filled in.
CREATE TABLE academy_requests (
    id               UUID         PRIMARY KEY,
    academy_id       UUID         NOT NULL REFERENCES academies (id),
    requested_by     UUID         NOT NULL,
    type             VARCHAR(30)  NOT NULL,
    status           VARCHAR(20)  NOT NULL DEFAULT 'PENDING',
    subject          VARCHAR(200),
    details          TEXT,
    target_email     VARCHAR(255),
    reason           VARCHAR(80),
    target_plan      VARCHAR(40),
    resolution_note  TEXT,
    resolved_by      UUID,
    resolved_at      TIMESTAMPTZ,
    created_at       TIMESTAMPTZ  NOT NULL DEFAULT now()
);
CREATE INDEX idx_academy_requests_academy ON academy_requests (academy_id, created_at DESC);
CREATE INDEX idx_academy_requests_status  ON academy_requests (status, created_at DESC);

-- One row per export an admin downloads, so Settings can list recent ones.
CREATE TABLE academy_exports (
    id          UUID         PRIMARY KEY,
    academy_id  UUID         NOT NULL REFERENCES academies (id),
    kind        VARCHAR(30)  NOT NULL,
    file_name   VARCHAR(120) NOT NULL,
    row_count   INTEGER      NOT NULL,
    size_bytes  BIGINT       NOT NULL,
    created_by  UUID         NOT NULL,
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT now()
);
CREATE INDEX idx_academy_exports_academy ON academy_exports (academy_id, created_at DESC);
