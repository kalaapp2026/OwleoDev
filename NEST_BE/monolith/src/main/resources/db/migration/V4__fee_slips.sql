-- Fee-slip billing cycle: "if I select the 2nd, fees are checked from last month's 2nd to this
-- month's 2nd and a fee slip is generated for every mapped student on that day" (course-level
-- config + generated record). Null billing_day_of_month means auto-billing stays off for that
-- course, matching every course's current behaviour before this migration ran.

ALTER TABLE courses ADD COLUMN billing_day_of_month INT;

CREATE TABLE fee_slips (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    membership_id UUID NOT NULL,
    course_id UUID NOT NULL,
    -- "YYYY-MM" of the billing date itself, matching fee_transactions.period so a slip's
    -- computed amount and a student's payments against it line up on the same key.
    period VARCHAR(7) NOT NULL,
    billing_period_start DATE NOT NULL,
    billing_period_end DATE NOT NULL,
    amount_due NUMERIC(12,2) NOT NULL,
    classes_held INT,
    classes_attended INT,
    generated_at TIMESTAMPTZ NOT NULL,
    CONSTRAINT uq_fee_slips_membership_course_period UNIQUE (membership_id, course_id, period)
);

CREATE INDEX idx_fee_slips_membership ON fee_slips (membership_id);
CREATE INDEX idx_fee_slips_course_period ON fee_slips (course_id, period);
