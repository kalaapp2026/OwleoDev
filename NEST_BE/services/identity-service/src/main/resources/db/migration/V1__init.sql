CREATE EXTENSION IF NOT EXISTS pgcrypto;

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
