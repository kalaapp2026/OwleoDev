-- An Academy Admin (or a Trainer with the right feature) can deactivate a student/trainer from a
-- single course without unenrolling them from their other courses. Deactivating hides that course
-- from the person and drops them from its rosters/pickers, but keeps the row so it's reversible.
ALTER TABLE course_map ADD COLUMN active BOOLEAN NOT NULL DEFAULT TRUE;
