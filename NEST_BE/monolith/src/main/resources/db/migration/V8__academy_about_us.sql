-- About-Us content (PRD 3.10) - previously intentionally not modelled (see V1's academies table
-- comment). Everyone in the academy can read this; only ACADEMY_ADMIN (feature ABOUT_US_EDIT,
-- non-delegable) can write it.

ALTER TABLE academies
    ADD COLUMN tagline VARCHAR(300),
    ADD COLUMN description TEXT,
    ADD COLUMN established_by VARCHAR(200),
    ADD COLUMN owner_name VARCHAR(200),
    ADD COLUMN additional_info TEXT,
    ADD COLUMN instagram_url VARCHAR(300),
    ADD COLUMN x_url VARCHAR(300),
    ADD COLUMN facebook_url VARCHAR(300),
    ADD COLUMN youtube_url VARCHAR(300);

-- "Describe about the course" blocks - hand-curated marketing copy for the About page (title +
-- description + picture), independent of the operational courses table so a deactivated/internal
-- course doesn't need to double as public-facing content.
CREATE TABLE academy_highlights (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    academy_id   UUID          NOT NULL,
    title        VARCHAR(200)  NOT NULL,
    description  TEXT,
    image_url    VARCHAR(500),
    order_index  INT           NOT NULL DEFAULT 0
);
CREATE INDEX idx_academy_highlights_academy ON academy_highlights (academy_id);

-- "Admin selects the trainer" - a real Trainer membership, not freeform text, so the name+photo
-- shown always matches that person's actual profile.
CREATE TABLE academy_featured_trainers (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    academy_id              UUID NOT NULL,
    trainer_membership_id   UUID NOT NULL,
    order_index             INT  NOT NULL DEFAULT 0
);
CREATE INDEX idx_academy_featured_trainers_academy ON academy_featured_trainers (academy_id);

CREATE TABLE academy_branches (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    academy_id   UUID          NOT NULL,
    name         VARCHAR(200)  NOT NULL,
    address      VARCHAR(500),
    order_index  INT           NOT NULL DEFAULT 0
);
CREATE INDEX idx_academy_branches_academy ON academy_branches (academy_id);
