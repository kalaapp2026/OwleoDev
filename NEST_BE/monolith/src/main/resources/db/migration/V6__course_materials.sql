-- Course Materials rework: a material can now target several batches at once instead of just
-- one (multi-select), and carries a real uploaded PDF/image attachment plus zero or more song
-- attachments (see tracks below) instead of a manually-typed URL.

ALTER TABLE syllabus_units DROP COLUMN batch_id;
ALTER TABLE syllabus_units ADD COLUMN reference_material_type VARCHAR(20) NOT NULL DEFAULT 'NONE';

-- Empty (no rows for a given syllabus_unit_id) means "applies to the whole course" - every
-- student/trainer enrolled in the course sees it. One or more rows means "only these batches".
-- No FK constraint, consistent with every other table in this schema (app-level referential
-- integrity throughout, not DB-enforced).
CREATE TABLE syllabus_unit_batches (
    syllabus_unit_id UUID NOT NULL,
    batch_id UUID NOT NULL,
    PRIMARY KEY (syllabus_unit_id, batch_id)
);
CREATE INDEX idx_syllabus_unit_batches_batch ON syllabus_unit_batches (batch_id);

-- "source" was a freeform placeholder from before real file upload existed; content_type is what
-- the player actually needs (audio/mpeg etc.), captured at upload time.
ALTER TABLE tracks DROP COLUMN source;
ALTER TABLE tracks ADD COLUMN content_type VARCHAR(100);
