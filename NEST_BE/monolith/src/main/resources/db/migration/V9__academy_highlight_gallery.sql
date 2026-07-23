-- Each "What we teach" highlight can now carry several photos, shown as a carousel, instead of
-- just one - replaces the single image_url column with a proper one-to-many table (same shape as
-- syllabus_unit_materials).
CREATE TABLE academy_highlight_images (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    highlight_id  UUID          NOT NULL,
    url           VARCHAR(500)  NOT NULL,
    order_index   INT           NOT NULL DEFAULT 0
);
CREATE INDEX idx_academy_highlight_images_highlight ON academy_highlight_images (highlight_id);

ALTER TABLE academy_highlights DROP COLUMN image_url;

-- Which trainer(s) (or Academy Admin, who can also teach) are shown on this highlight's card -
-- tapping the block opens the full detail (all photos, full description, every trainer listed).
CREATE TABLE academy_highlight_trainers (
    highlight_id            UUID NOT NULL,
    trainer_membership_id   UUID NOT NULL,
    PRIMARY KEY (highlight_id, trainer_membership_id)
);
CREATE INDEX idx_academy_highlight_trainers_highlight ON academy_highlight_trainers (highlight_id);
