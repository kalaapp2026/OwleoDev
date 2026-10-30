-- Study material is shared with an AUDIENCE, not with one batch.
--
-- A file can be aimed at whole courses (every student enrolled in them gets it, batch or no batch)
-- and/or at batches (the students in them). Before this a material belonged to exactly one batch, so a
-- course with no batches had nowhere to put a file, and a batch spanning Basic + Advanced could not
-- hand Advanced students something Basic students would not see.
--
-- Additive, same pattern as batch_trainers / batch_courses: study_materials.batch_id stays as the
-- material's "home batch" (the first batch it was aimed at, null for a course-only file), and the full
-- audience lives here.
CREATE TABLE study_material_targets (
    material_id UUID        NOT NULL,
    target_type VARCHAR(10) NOT NULL,
    target_id   UUID        NOT NULL,
    PRIMARY KEY (material_id, target_type, target_id),
    CONSTRAINT ck_study_material_target_type CHECK (target_type IN ('COURSE', 'BATCH'))
);

CREATE INDEX idx_study_material_targets_target ON study_material_targets (target_type, target_id);

-- Every existing file keeps meaning exactly what it meant: shared with its one batch.
INSERT INTO study_material_targets (material_id, target_type, target_id)
SELECT id, 'BATCH', batch_id FROM study_materials;

-- A file aimed only at courses has no home batch.
ALTER TABLE study_materials ALTER COLUMN batch_id DROP NOT NULL;
