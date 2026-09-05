-- Schedule & Reschedule module: the single-session overrides an admin can apply to one class
-- without touching the batch's recurring pattern.
--
-- Reschedule already existed (reschedule_reason + original_instance_id). This adds the other two
-- overrides the schedule screen offers - cancelling one session, and swapping in a substitute
-- instructor for one session - plus the reason each carries.

-- ---------------------------------------------------------------------------
-- Substitute instructor
-- ---------------------------------------------------------------------------
-- Set on the instance itself rather than by editing batch_trainers: the batch's usual trainers
-- are unchanged, this is "someone else is covering, this once". Reading the instance therefore
-- tells you both who is actually teaching and who normally would.
ALTER TABLE class_instances ADD COLUMN substitute_trainer_membership_id UUID;
ALTER TABLE class_instances ADD COLUMN substitution_reason VARCHAR(300);

CREATE INDEX idx_class_instances_substitute
    ON class_instances (substitute_trainer_membership_id)
    WHERE substitute_trainer_membership_id IS NOT NULL;

-- A reason without a substitute would be a reason for nothing; the pair moves together.
ALTER TABLE class_instances ADD CONSTRAINT ck_class_instances_substitution
    CHECK (substitution_reason IS NULL OR substitute_trainer_membership_id IS NOT NULL);

-- ---------------------------------------------------------------------------
-- Cancellation
-- ---------------------------------------------------------------------------
-- Kept separate from reschedule_reason instead of sharing one "reason" column. A session can be
-- moved and then the moved session cancelled, and collapsing the two would overwrite the first
-- explanation with the second - losing exactly the history this table exists to preserve.
ALTER TABLE class_instances ADD COLUMN cancellation_reason VARCHAR(300);
