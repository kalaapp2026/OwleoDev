-- Study Material: files a trainer shares with one batch.
--
-- A new table rather than an extension of syllabus_units, because the two answer different
-- questions. A syllabus unit is curriculum structure - what the course teaches, in order, scoped
-- to a course. Study material is a file drop for one batch: this week's chord chart, a backing
-- track, a photo of the board. Forcing the latter through the former would mean inventing a
-- syllabus unit every time someone shares a PDF.

CREATE TABLE study_materials (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    batch_id      UUID          NOT NULL,
    title         VARCHAR(200)  NOT NULL,
    description   VARCHAR(200),

    url           VARCHAR(500)  NOT NULL,
    file_name     VARCHAR(300)  NOT NULL,
    content_type  VARCHAR(120),
    -- NOTES / AUDIO / IMAGE. Derived from the uploaded file's extension at upload time and
    -- stored, so the list can group and filter by type without re-sniffing every file.
    file_type     VARCHAR(20)   NOT NULL,
    size_bytes    BIGINT        NOT NULL DEFAULT 0,

    -- DOWNLOADABLE / VIEW_ONLY. The point of the whole feature for a music academy: a backing
    -- track can be listened to in-app without handing out a redistributable file.
    permission    VARCHAR(20)   NOT NULL DEFAULT 'DOWNLOADABLE',

    uploaded_by   UUID          NOT NULL,
    uploaded_at   TIMESTAMPTZ   NOT NULL DEFAULT now()
);

CREATE INDEX idx_study_materials_batch ON study_materials (batch_id);

-- The batch list orders by most-recently-updated, which is this column descending per batch.
CREATE INDEX idx_study_materials_batch_uploaded ON study_materials (batch_id, uploaded_at DESC);
