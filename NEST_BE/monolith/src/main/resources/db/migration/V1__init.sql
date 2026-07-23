CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ============================= identity =============================

CREATE TABLE users (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    username                VARCHAR(100) NOT NULL,
    full_name               VARCHAR(200) NOT NULL,
    phone                   VARCHAR(512) NOT NULL,
    phone_hash              VARCHAR(64)  NOT NULL,
    email                   VARCHAR(200),
    dob                     VARCHAR(512),
    address                 VARCHAR(1024),
    city                    VARCHAR(100),
    state                   VARCHAR(100),
    role_type               VARCHAR(30)  NOT NULL,
    password_hash           VARCHAR(200),
    is_temporary_password   BOOLEAN      NOT NULL DEFAULT FALSE,
    theme_preference        VARCHAR(20)  NOT NULL DEFAULT 'SYSTEM',
    status                  VARCHAR(20)  NOT NULL DEFAULT 'ACTIVE',
    created_at              TIMESTAMPTZ,
    updated_at              TIMESTAMPTZ,
    CONSTRAINT uq_users_username UNIQUE (username),
    CONSTRAINT uq_users_phone_hash UNIQUE (phone_hash)
);

CREATE TABLE academy_memberships (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id      UUID        NOT NULL,
    academy_id   UUID        NOT NULL,
    academy_name VARCHAR(200),
    role_type    VARCHAR(30) NOT NULL,
    status       VARCHAR(30) NOT NULL DEFAULT 'ACTIVE',
    created_by   UUID,
    created_at   TIMESTAMPTZ
);
CREATE INDEX idx_membership_user ON academy_memberships (user_id);
CREATE INDEX idx_membership_academy ON academy_memberships (academy_id);

CREATE TABLE feature_grants (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    membership_id UUID        NOT NULL,
    feature_key   VARCHAR(50) NOT NULL,
    granted_by    UUID,
    created_at    TIMESTAMPTZ,
    CONSTRAINT uq_feature_grants_membership_feature UNIQUE (membership_id, feature_key)
);
CREATE INDEX idx_feature_grants_membership ON feature_grants (membership_id);

CREATE TABLE course_map (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    membership_id UUID NOT NULL,
    course_id     UUID NOT NULL,
    agreed_fee    NUMERIC(12, 2),
    CONSTRAINT uq_course_map_membership_course UNIQUE (membership_id, course_id)
);
CREATE INDEX idx_course_map_membership ON course_map (membership_id);

CREATE TABLE otp_verifications (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    phone_hash  VARCHAR(64) NOT NULL,
    code_hash   VARCHAR(200) NOT NULL,
    purpose     VARCHAR(30) NOT NULL,
    context_id  UUID,
    attempts    INTEGER     NOT NULL DEFAULT 0,
    consumed    BOOLEAN     NOT NULL DEFAULT FALSE,
    expires_at  TIMESTAMPTZ NOT NULL,
    created_at  TIMESTAMPTZ
);
CREATE INDEX idx_otp_phone_hash ON otp_verifications (phone_hash);

-- ============================= academy =============================

CREATE TABLE academies (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name           VARCHAR(200) NOT NULL,
    category       VARCHAR(30)  NOT NULL,
    logo_url       VARCHAR(500),
    address        VARCHAR(500) NOT NULL,
    city           VARCHAR(100) NOT NULL,
    state          VARCHAR(100) NOT NULL,
    contact_number VARCHAR(30)  NOT NULL,
    email          VARCHAR(200),
    plan           VARCHAR(50)  NOT NULL DEFAULT 'STANDARD',
    status         VARCHAR(20)  NOT NULL DEFAULT 'ACTIVE',
    created_at     TIMESTAMPTZ,
    updated_at     TIMESTAMPTZ,
    CONSTRAINT uq_academies_name_city UNIQUE (name, city)
);

-- ============================= curriculum =============================

CREATE TABLE courses (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    academy_id     UUID          NOT NULL,
    category       VARCHAR(30)   NOT NULL,
    name           VARCHAR(200)  NOT NULL,
    description    TEXT,
    duration_level VARCHAR(100),
    default_fee    NUMERIC(12,2) NOT NULL,
    fee_cycle      VARCHAR(20)   NOT NULL,
    thumbnail_url  VARCHAR(500),
    status         VARCHAR(20)   NOT NULL DEFAULT 'ACTIVE',
    created_at     TIMESTAMPTZ,
    updated_at     TIMESTAMPTZ
);
CREATE INDEX idx_courses_academy ON courses (academy_id);

CREATE TABLE syllabus_units (
    id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    course_id             UUID         NOT NULL,
    batch_id              UUID,
    title                 VARCHAR(200) NOT NULL,
    description           TEXT,
    reference_material_url VARCHAR(500),
    order_index           INTEGER      NOT NULL DEFAULT 0,
    status                VARCHAR(20)  NOT NULL DEFAULT 'NOT_STARTED'
);
CREATE INDEX idx_syllabus_course ON syllabus_units (course_id);

CREATE TABLE tracks (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    syllabus_unit_id  UUID         NOT NULL,
    title             VARCHAR(200) NOT NULL,
    source            VARCHAR(200),
    storage_key       VARCHAR(500) NOT NULL,
    stream_only       BOOLEAN      NOT NULL DEFAULT TRUE
);
CREATE INDEX idx_tracks_syllabus_unit ON tracks (syllabus_unit_id);

-- ============================= enrolment =============================

CREATE TABLE batches (
    id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    course_id            UUID         NOT NULL,
    name                 VARCHAR(200) NOT NULL,
    description          VARCHAR(500),
    batch_type           VARCHAR(20)  NOT NULL,
    trainer_membership_id UUID,
    status               VARCHAR(20)  NOT NULL DEFAULT 'ACTIVE'
);
CREATE INDEX idx_batches_course ON batches (course_id);

CREATE TABLE batch_members (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    batch_id      UUID NOT NULL,
    membership_id UUID NOT NULL,
    joined_at     TIMESTAMPTZ,
    CONSTRAINT uq_batch_members_batch_membership UNIQUE (batch_id, membership_id)
);
CREATE INDEX idx_batch_members_batch ON batch_members (batch_id);
CREATE INDEX idx_batch_members_membership ON batch_members (membership_id);

-- ============================= scheduling =============================

CREATE TABLE schedules (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    batch_id       UUID        NOT NULL,
    day_of_week    VARCHAR(10) NOT NULL,
    start_time     TIME        NOT NULL,
    end_time       TIME        NOT NULL,
    effective_from DATE        NOT NULL,
    effective_to   DATE
);
CREATE INDEX idx_schedules_batch ON schedules (batch_id);

CREATE TABLE class_instances (
    id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    batch_id             UUID        NOT NULL,
    schedule_id          UUID,
    date                 DATE        NOT NULL,
    start_time           TIME        NOT NULL,
    end_time             TIME        NOT NULL,
    status               VARCHAR(30) NOT NULL DEFAULT 'SCHEDULED',
    reschedule_reason    VARCHAR(500),
    original_instance_id UUID
);
CREATE INDEX idx_class_instances_batch ON class_instances (batch_id);
CREATE INDEX idx_class_instances_date ON class_instances (date);

-- ============================= attendance =============================

CREATE TABLE attendance (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    class_instance_id UUID        NOT NULL,
    membership_id     UUID        NOT NULL,
    status            VARCHAR(20) NOT NULL,
    marked_by         UUID        NOT NULL,
    marked_at         TIMESTAMPTZ NOT NULL,
    note              VARCHAR(500),
    CONSTRAINT uq_attendance_instance_membership UNIQUE (class_instance_id, membership_id)
);
CREATE INDEX idx_attendance_class_instance ON attendance (class_instance_id);
CREATE INDEX idx_attendance_membership ON attendance (membership_id);

-- ============================= fees =============================

CREATE TABLE fee_transactions (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    membership_id UUID          NOT NULL,
    course_id     UUID          NOT NULL,
    period        VARCHAR(20)   NOT NULL,
    amount_paid   NUMERIC(12,2) NOT NULL,
    mode          VARCHAR(20)   NOT NULL,
    note          VARCHAR(500),
    recorded_by   UUID          NOT NULL,
    gateway_ref   VARCHAR(200),
    created_at    TIMESTAMPTZ
);
CREATE INDEX idx_fee_tx_membership ON fee_transactions (membership_id);
CREATE INDEX idx_fee_tx_membership_course_period ON fee_transactions (membership_id, course_id, period);

-- ============================= events =============================

CREATE TABLE events (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    academy_id      UUID         NOT NULL,
    type            VARCHAR(30)  NOT NULL,
    title           VARCHAR(200) NOT NULL,
    description     TEXT,
    event_date      TIMESTAMP    NOT NULL,
    location        VARCHAR(300),
    visibility      VARCHAR(20)  NOT NULL,
    cover_image_url VARCHAR(500),
    created_by      UUID         NOT NULL,
    created_at      TIMESTAMPTZ
);
CREATE INDEX idx_events_academy ON events (academy_id);

-- ============================= social =============================

CREATE TABLE posts (
    id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    author_membership_id UUID,
    author_user_id       UUID,
    type                 VARCHAR(20) NOT NULL,
    content              TEXT,
    visibility           VARCHAR(20) NOT NULL,
    event_id             UUID,
    created_at           TIMESTAMPTZ
);
CREATE INDEX idx_posts_author_membership ON posts (author_membership_id);
CREATE INDEX idx_posts_visibility ON posts (visibility);

CREATE TABLE post_media_urls (
    post_id   UUID NOT NULL REFERENCES posts (id) ON DELETE CASCADE,
    media_url VARCHAR(500) NOT NULL
);
CREATE INDEX idx_post_media_urls_post ON post_media_urls (post_id);

CREATE TABLE interests (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id    UUID NOT NULL,
    event_id   UUID,
    post_id    UUID,
    created_at TIMESTAMPTZ
);
CREATE INDEX idx_interests_user ON interests (user_id);

-- ============================= audit =============================

CREATE TABLE audit_log (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    occurred_at         TIMESTAMPTZ  NOT NULL,
    actor_user_id       UUID,
    actor_membership_id UUID,
    action              VARCHAR(100) NOT NULL,
    entity_type         VARCHAR(100) NOT NULL,
    entity_id           VARCHAR(100),
    source              VARCHAR(100) NOT NULL,
    detail              VARCHAR(2000),
    created_at          TIMESTAMPTZ  NOT NULL
);
CREATE INDEX idx_audit_entity ON audit_log (entity_type, entity_id);
CREATE INDEX idx_audit_actor ON audit_log (actor_user_id);
CREATE INDEX idx_audit_created_at ON audit_log (created_at);
