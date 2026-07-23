-- A material can now carry more than one PDF/image, not just one - replaces the single
-- reference_material_url/type pair on syllabus_units with a proper one-to-many table (same shape
-- as tracks, which already worked this way for songs).

CREATE TABLE syllabus_unit_materials (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    syllabus_unit_id  UUID          NOT NULL,
    url               VARCHAR(500)  NOT NULL,
    material_type     VARCHAR(20)   NOT NULL,
    content_type      VARCHAR(100),
    uploaded_at       TIMESTAMPTZ   NOT NULL DEFAULT now()
);
CREATE INDEX idx_syllabus_unit_materials_unit ON syllabus_unit_materials (syllabus_unit_id);

ALTER TABLE syllabus_units DROP COLUMN reference_material_url;
ALTER TABLE syllabus_units DROP COLUMN reference_material_type;
