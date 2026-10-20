-- HQ: platform-wide master data, the profile fields every academy must collect, exit management,
-- and the history of what HQ changed on a person.

-- Lists HQ maintains for every academy. Deactivating an item hides it from new choices; records
-- that already use it keep it, so nothing is deleted.
CREATE TABLE hq_master_items (
    id         UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    kind       VARCHAR(12)  NOT NULL CHECK (kind IN ('BATCH_TYPE', 'ROLE', 'CATEGORY')),
    name       VARCHAR(80)  NOT NULL,
    active     BOOLEAN      NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ  NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX uq_hq_master_item ON hq_master_items (kind, lower(name));

INSERT INTO hq_master_items (kind, name, active) VALUES
    ('BATCH_TYPE', 'Weekday evening', TRUE), ('BATCH_TYPE', 'Weekday morning', TRUE), ('BATCH_TYPE', 'Weekend', TRUE),
    ('BATCH_TYPE', 'Online', TRUE), ('BATCH_TYPE', 'Crash course', TRUE), ('BATCH_TYPE', 'Summer camp', FALSE),
    ('ROLE', 'Owner', TRUE), ('ROLE', 'Academy admin', TRUE), ('ROLE', 'Trainer', TRUE), ('ROLE', 'Student', TRUE),
    ('ROLE', 'Parent or guardian', TRUE), ('ROLE', 'Accountant', TRUE),
    ('CATEGORY', 'Dance', TRUE), ('CATEGORY', 'Music', TRUE), ('CATEGORY', 'Fine Arts', TRUE), ('CATEGORY', 'Theatre', TRUE);

-- Profile fields HQ requires on every account. A person missing one is flagged in Users.
CREATE TABLE hq_required_fields (
    field    VARCHAR(12)  PRIMARY KEY,
    label    VARCHAR(60)  NOT NULL,
    required BOOLEAN      NOT NULL DEFAULT FALSE,
    position SMALLINT     NOT NULL
);
INSERT INTO hq_required_fields (field, label, required, position) VALUES
    ('email', 'Email', TRUE, 1), ('addr', 'Address', TRUE, 2), ('dob', 'Date of birth', TRUE, 3),
    ('emer', 'Emergency contact', TRUE, 4), ('guard', 'Guardian details (under 18)', TRUE, 5), ('photo', 'Profile photo', FALSE, 6);

-- What HQ changed on a person, and every activation and deactivation, with the reason.
CREATE TABLE hq_user_history (
    id         UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id    UUID         NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    kind       VARCHAR(8)   NOT NULL CHECK (kind IN ('CHANGE', 'STATUS')),
    field      VARCHAR(60),
    from_value VARCHAR(200),
    to_value   VARCHAR(200),
    reason     VARCHAR(200),
    actor_name VARCHAR(120) NOT NULL,
    at         TIMESTAMPTZ  NOT NULL DEFAULT now()
);
CREATE INDEX idx_hq_user_history_user ON hq_user_history (user_id, at DESC);

-- A person leaving: routed through the EXIT workflow, then three clearances, then access is removed.
-- academy_id NULL means every academy they belong to; otherwise only that one is removed.
CREATE TABLE hq_exits (
    id           UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    seq          BIGSERIAL,
    user_id      UUID         NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    academy_id   UUID         REFERENCES academies (id) ON DELETE CASCADE,
    reason       VARCHAR(200) NOT NULL,
    effective_on DATE         NOT NULL,
    stage        VARCHAR(10)  NOT NULL DEFAULT 'APPROVAL' CHECK (stage IN ('APPROVAL', 'CLEARANCE', 'DONE', 'REJECTED')),
    c_dues       BOOLEAN      NOT NULL DEFAULT FALSE,
    c_handover   BOOLEAN      NOT NULL DEFAULT FALSE,
    c_assets     BOOLEAN      NOT NULL DEFAULT FALSE,
    approval_id  UUID         REFERENCES hq_requests (id) ON DELETE SET NULL,
    created_at   TIMESTAMPTZ  NOT NULL DEFAULT now(),
    done_at      TIMESTAMPTZ
);
CREATE INDEX idx_hq_exits_user ON hq_exits (user_id);
