-- A student moves from one course to another on a future date - Basic to Advanced from the 1st of next
-- month - so the new course's fee starts from that month's slip and the old course stops billing, without
-- rewriting the slip already issued for this one.
--
-- Nothing changes on the day it is scheduled. A job applies each due row: it activates the new
-- enrolment, deactivates the old one, and moves the student between batches. Everything that already
-- reads course_map.active (rosters, fee slips, study material, attendance) then simply sees the new
-- state from that day on.
CREATE TABLE student_course_changes (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    membership_id  UUID        NOT NULL,
    from_course_id UUID        NOT NULL,
    to_course_id   UUID        NOT NULL,
    effective_on   DATE        NOT NULL,
    -- Batches of the new course to place the student in when it takes effect, comma-separated ids.
    to_batch_ids   VARCHAR(2000),
    status         VARCHAR(10) NOT NULL DEFAULT 'PENDING',
    created_by     UUID        NOT NULL,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    applied_at     TIMESTAMPTZ,
    CONSTRAINT ck_student_course_changes_status CHECK (status IN ('PENDING', 'APPLIED', 'CANCELLED')),
    CONSTRAINT ck_student_course_changes_courses CHECK (from_course_id <> to_course_id)
);

CREATE INDEX idx_student_course_changes_due ON student_course_changes (status, effective_on);
CREATE INDEX idx_student_course_changes_member ON student_course_changes (membership_id);
