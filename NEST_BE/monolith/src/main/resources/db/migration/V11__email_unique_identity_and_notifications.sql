-- Phone can no longer be the platform-wide identity key: a parent registering two children hands
-- out the same phone number for both. Email becomes the dedup key instead; username stays unique.
ALTER TABLE users DROP CONSTRAINT uq_users_phone_hash;
CREATE UNIQUE INDEX uq_users_email_lower ON users (LOWER(email)) WHERE email IS NOT NULL;

-- Course(s) staged on an ALREADY-ACTIVE membership that the registering Trainer/Admin can't
-- currently see (no course-map overlap) - applied once the member themselves confirms via OTP,
-- same as a brand new PENDING_CONFIRMATION membership (StudentRegistrationService).
CREATE TABLE membership_pending_course_fees (
    membership_id UUID NOT NULL,
    course_id     UUID NOT NULL,
    fee           NUMERIC(12, 2),
    PRIMARY KEY (membership_id, course_id)
);

-- In-app notification feed (Notifications tab) - starts out carrying only membership-confirmation
-- OTP codes; the type column leaves room for other kinds later without a schema change.
CREATE TABLE app_notifications (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID         NOT NULL,
    type        VARCHAR(40)  NOT NULL,
    title       VARCHAR(200) NOT NULL,
    body        VARCHAR(1000) NOT NULL,
    action_code VARCHAR(20),
    read_at     TIMESTAMPTZ,
    created_at  TIMESTAMPTZ
);
CREATE INDEX idx_app_notifications_user ON app_notifications (user_id, created_at DESC);
