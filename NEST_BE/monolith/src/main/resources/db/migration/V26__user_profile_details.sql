-- User Creation: the fields the registration form collects but had nowhere to store.
--
-- The existing users table carries full_name / phone / address / city / state, which was enough
-- for a login. A registration form replacing a paper enrolment slip asks for considerably more,
-- and the parts an academy actually needs in an emergency (guardian, blood group) were the ones
-- with no home at all.

-- ---------------------------------------------------------------------------
-- Name
-- ---------------------------------------------------------------------------
-- Kept alongside full_name rather than replacing it. full_name is what every existing screen,
-- notification and audit row reads, and it stays the authoritative display value; these two are
-- for pre-filling the form's separate First/Last fields on edit without guessing at where to
-- split a name that may have any number of parts.
ALTER TABLE users ADD COLUMN first_name VARCHAR(100);
ALTER TABLE users ADD COLUMN last_name  VARCHAR(100);

-- ---------------------------------------------------------------------------
-- Personal details
-- ---------------------------------------------------------------------------
ALTER TABLE users ADD COLUMN gender      VARCHAR(20);
ALTER TABLE users ADD COLUMN blood_group VARCHAR(5);

-- Encrypted like the primary phone (see users.phone, VARCHAR(512) for the same reason) - an
-- alternate number is exactly as identifying as the main one.
ALTER TABLE users ADD COLUMN alt_phone   VARCHAR(512);

ALTER TABLE users ADD COLUMN photo_url   VARCHAR(500);

-- ---------------------------------------------------------------------------
-- Structured address
-- ---------------------------------------------------------------------------
-- The existing single-line `address` column stays and keeps working; these break out the parts
-- the form asks for separately. Nothing back-fills them from the free-text column: parsing an
-- arbitrary address into lines and a PIN code guesses, and a wrong PIN code is worse than none.
ALTER TABLE users ADD COLUMN address_line2 VARCHAR(200);
ALTER TABLE users ADD COLUMN landmark      VARCHAR(200);
ALTER TABLE users ADD COLUMN district      VARCHAR(100);
ALTER TABLE users ADD COLUMN country       VARCHAR(100);
ALTER TABLE users ADD COLUMN pin_code      VARCHAR(12);

-- ---------------------------------------------------------------------------
-- Student-only
-- ---------------------------------------------------------------------------
ALTER TABLE users ADD COLUMN guardian_name      VARCHAR(200);
-- Encrypted for the same reason as the other phone columns.
ALTER TABLE users ADD COLUMN emergency_contact  VARCHAR(512);

-- ---------------------------------------------------------------------------
-- Trainer-only
-- ---------------------------------------------------------------------------
-- Free text rather than a qualification lookup: the range runs from "Trinity Grade 8" to
-- "Bharatanatyam Visharad, 12 yrs stage experience", and no fixed vocabulary covers both.
ALTER TABLE users ADD COLUMN qualification VARCHAR(300);

-- ---------------------------------------------------------------------------
-- Membership
-- ---------------------------------------------------------------------------
-- The date this person joined THIS academy, which is a property of the membership rather than
-- the user: the same person can join a second academy years later, and users.created_at answers
-- a different question ("when did this account first exist").
ALTER TABLE academy_memberships ADD COLUMN joining_date DATE;

-- ---------------------------------------------------------------------------
-- Trainer course mapping: batches
-- ---------------------------------------------------------------------------
-- course_feature_grants already records which features a trainer holds on a course. The form
-- also scopes a trainer to specific batches within it ("Attendance, but only for Batch A"), which
-- had nowhere to live.
CREATE TABLE trainer_course_batches (
    membership_id UUID NOT NULL,
    course_id     UUID NOT NULL,
    batch_id      UUID NOT NULL,
    PRIMARY KEY (membership_id, course_id, batch_id)
);

CREATE INDEX idx_trainer_course_batches_membership ON trainer_course_batches (membership_id);

-- No rows are seeded. An empty set for a course means "every batch on it", which is exactly the
-- access existing trainers already have - back-filling one row per current batch would instead
-- freeze them out of any batch created afterwards.
