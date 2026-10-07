-- Student self-service: interest in courses the student is not yet enrolled in, a request to have
-- the account deleted (approved by the academy admin, never self-executed), and per-user
-- notification preferences. No FK constraints, same as the rest of this schema.
CREATE TABLE course_interests (
    id            UUID PRIMARY KEY,
    academy_id    UUID NOT NULL,
    course_id     UUID NOT NULL,
    membership_id UUID NOT NULL,
    created_at    TIMESTAMP NOT NULL DEFAULT now(),
    CONSTRAINT uq_course_interest UNIQUE (course_id, membership_id)
);
CREATE INDEX idx_course_interests_membership ON course_interests (membership_id);

CREATE TABLE account_deletion_requests (
    id            UUID PRIMARY KEY,
    user_id       UUID NOT NULL,
    membership_id UUID NOT NULL,
    academy_id    UUID NOT NULL,
    status        VARCHAR(20) NOT NULL DEFAULT 'PENDING',
    created_at    TIMESTAMP NOT NULL DEFAULT now()
);
CREATE INDEX idx_deletion_requests_academy ON account_deletion_requests (academy_id, status);

ALTER TABLE users ADD COLUMN notify_attendance BOOLEAN NOT NULL DEFAULT TRUE;
ALTER TABLE users ADD COLUMN notify_events     BOOLEAN NOT NULL DEFAULT TRUE;
ALTER TABLE users ADD COLUMN notify_study      BOOLEAN NOT NULL DEFAULT FALSE;
