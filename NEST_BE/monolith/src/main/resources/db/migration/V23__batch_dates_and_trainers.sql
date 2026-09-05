-- Batch Creation module: the fields the batch form collects but had nowhere to store.
--
--   1. Start/end dates - a Temporary batch runs between two dates, and even a Regular batch has
--      a day it starts from.
--   2. Multiple trainers per batch.

-- ---------------------------------------------------------------------------
-- 1. Dates
-- ---------------------------------------------------------------------------
-- start_date is nullable rather than NOT NULL DEFAULT today: back-filling every existing batch
-- with today's date would assert something false about batches that have been running for months,
-- and the schedule's own effective_from already carries the real "classes begin" date for those.
ALTER TABLE batches ADD COLUMN start_date DATE;

-- Only meaningful for TEMPORARY batches; a Regular batch runs until deactivated. The CHECK
-- allows an open-ended temporary batch (end_date NULL) but never an end before the start.
ALTER TABLE batches ADD COLUMN end_date DATE;
ALTER TABLE batches ADD CONSTRAINT ck_batches_date_order
    CHECK (start_date IS NULL OR end_date IS NULL OR end_date >= start_date);

-- ---------------------------------------------------------------------------
-- 2. Trainers
-- ---------------------------------------------------------------------------
-- Additive on purpose. batches.trainer_membership_id stays as the batch's primary trainer, so
-- every existing query (Calendar's "a Trainer's own classes", the batch list's trainer name,
-- syllabus visibility) keeps working untouched. This table carries the full set for batches that
-- have more than one, and the primary is mirrored into it so callers that want "all trainers"
-- read one place rather than unioning a column with a table.
CREATE TABLE batch_trainers (
    batch_id             UUID NOT NULL,
    trainer_membership_id UUID NOT NULL,
    PRIMARY KEY (batch_id, trainer_membership_id)
);

CREATE INDEX idx_batch_trainers_membership ON batch_trainers (trainer_membership_id);

-- Seed from the existing single-trainer column so the join table is the complete picture from
-- the moment it exists, not just for batches edited after this migration.
INSERT INTO batch_trainers (batch_id, trainer_membership_id)
SELECT id, trainer_membership_id
FROM batches
WHERE trainer_membership_id IS NOT NULL;
