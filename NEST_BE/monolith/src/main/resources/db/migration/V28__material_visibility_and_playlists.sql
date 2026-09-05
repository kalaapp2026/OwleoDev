-- Study Material, second pass: per-student visibility, playlists, and saved playback settings.
--
-- V25 gave a material one owner (a batch) and one permission (downloadable or view-only). The
-- three things below are what the batch-wide model could not express.

-- ---------------------------------------------------------------------------
-- Visibility: the whole batch, or named students
-- ---------------------------------------------------------------------------
-- ALL is the overwhelming common case and stays the default, so nothing already uploaded changes
-- meaning. SELECTED exists for the material that is genuinely for one person - a correction for
-- the student who missed a class, an exam piece assigned to one candidate - which under the
-- batch-wide model could only be shared by sharing it with everyone.
ALTER TABLE study_materials
    ADD COLUMN visibility VARCHAR(20) NOT NULL DEFAULT 'ALL';

CREATE TABLE study_material_students (
    material_id   UUID NOT NULL,
    membership_id UUID NOT NULL,
    PRIMARY KEY (material_id, membership_id)
);

CREATE INDEX idx_study_material_students_membership
    ON study_material_students (membership_id);

-- ---------------------------------------------------------------------------
-- Playlists
-- ---------------------------------------------------------------------------
-- A trainer's own running order over the audio already uploaded - warm-ups, then the piece, then
-- the cool-down - so a class does not mean hunting for the next file between every exercise.
--
-- Owned by a membership, not a user: a trainer teaching at two academies keeps a separate set at
-- each, and the materials a playlist points at are that academy's anyway.
CREATE TABLE material_playlists (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    membership_id UUID          NOT NULL,
    academy_id    UUID          NOT NULL,
    name          VARCHAR(120)  NOT NULL,
    created_at    TIMESTAMPTZ   NOT NULL DEFAULT now()
);

CREATE INDEX idx_material_playlists_membership ON material_playlists (membership_id);

-- Entries carry their own id rather than being keyed by (playlist, material). The same piece
-- legitimately appears more than once in one running order - played slowly, then up to tempo -
-- and each appearance needs its own position, so a composite key on the material would collapse
-- the two into one row.
CREATE TABLE material_playlist_entries (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    playlist_id UUID    NOT NULL,
    material_id UUID    NOT NULL,
    position    INTEGER NOT NULL
);

CREATE INDEX idx_material_playlist_entries_playlist
    ON material_playlist_entries (playlist_id, position);

-- ---------------------------------------------------------------------------
-- Saved playback settings
-- ---------------------------------------------------------------------------
-- Per person per track, not per track: two trainers practising the same piece want different
-- tempos, and one overwriting the other's would make the feature worse than not having it.
--
-- `segments` is JSONB rather than its own table: it is a short ordered list read and written whole
-- ([{start, end, speed}], the parts of a file to play back-to-back with the rest skipped), never
-- queried across rows, and a table would buy joins for something that is always fetched as one
-- opaque value alongside its parent.
CREATE TABLE material_playback_settings (
    membership_id UUID    NOT NULL,
    material_id   UUID    NOT NULL,
    speed         NUMERIC(4, 2) NOT NULL DEFAULT 1.00,
    volume        INTEGER NOT NULL DEFAULT 80,
    loop_enabled  BOOLEAN NOT NULL DEFAULT FALSE,
    segments      JSONB,
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (membership_id, material_id),

    -- The player's arcs run 0.25x-2x and 0-100. Clamping in the UI is not enough: these values
    -- come back out and drive playback, and an out-of-range speed is inaudible noise.
    CONSTRAINT chk_playback_speed  CHECK (speed >= 0.25 AND speed <= 2.00),
    CONSTRAINT chk_playback_volume CHECK (volume >= 0 AND volume <= 100)
);
