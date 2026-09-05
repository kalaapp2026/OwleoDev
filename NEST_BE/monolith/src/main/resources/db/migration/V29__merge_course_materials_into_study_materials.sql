-- Course Materials and Study Material were the same feature wearing two models, so this folds the
-- first into the second.
--
-- What survives is the batch-first file drop: one row per file, typed NOTES/AUDIO/IMAGE, marked
-- DOWNLOADABLE or VIEW_ONLY. What goes is the syllabus unit as a container - ordered chapters and
-- their NOT_STARTED/IN_PROGRESS/COMPLETED status - which has no equivalent on the surviving side.
--
-- The unit does not become a material. Its files and songs do, and the unit's title comes along on
-- each of them so a file that used to read as "Chapter 1's backing track" still says which chapter
-- it belonged to.

-- ---------------------------------------------------------------------------
-- Attachments (PDF / image) -> study_materials
-- ---------------------------------------------------------------------------
-- A unit reaches a batch two ways: it named that batch explicitly, or it was course-wide and so
-- applied to every batch on the course. Both are unioned here, and DISTINCT collapses the overlap
-- rather than letting a unit that is both course-wide and explicitly targeted produce duplicates.
WITH unit_batches AS (
    SELECT DISTINCT su.id AS unit_id, b.id AS batch_id
    FROM nest.syllabus_units su
    JOIN nest.batches b ON b.course_id = su.course_id
    WHERE NOT EXISTS (SELECT 1 FROM nest.syllabus_unit_batches sub WHERE sub.syllabus_unit_id = su.id)

    UNION

    SELECT sub.syllabus_unit_id, sub.batch_id
    FROM nest.syllabus_unit_batches sub
),
-- study_materials.uploaded_by is NOT NULL but neither source table recorded an uploader. The
-- academy's own admin is the honest stand-in: the material demonstrably belongs to that academy,
-- and inventing a UUID would point at nobody.
academy_admin AS (
    SELECT c.id AS course_id, (
        SELECT m.user_id
        FROM nest.academy_memberships m
        WHERE m.academy_id = c.academy_id
          AND m.role_type = 'ACADEMY_ADMIN'
          AND m.status = 'ACTIVE'
        ORDER BY m.id
        LIMIT 1
    ) AS user_id
    FROM nest.courses c
)
INSERT INTO nest.study_materials
    (batch_id, title, description, url, file_name, content_type, file_type, size_bytes,
     permission, visibility, uploaded_by, uploaded_at)
SELECT
    ub.batch_id,
    su.title,
    su.description,
    sum_.url,
    -- No filename was ever stored; the last path segment of the URL is the closest true answer.
    regexp_replace(sum_.url, '^.*/', ''),
    sum_.content_type,
    CASE WHEN sum_.material_type = 'IMAGE' THEN 'IMAGE' ELSE 'NOTES' END,
    0,
    -- Attachments had no per-file permission, and the old screen always offered them for download.
    'DOWNLOADABLE',
    'ALL',
    aa.user_id,
    sum_.uploaded_at
FROM nest.syllabus_unit_materials sum_
JOIN nest.syllabus_units su ON su.id = sum_.syllabus_unit_id
JOIN unit_batches ub ON ub.unit_id = su.id
JOIN academy_admin aa ON aa.course_id = su.course_id
WHERE aa.user_id IS NOT NULL;

-- ---------------------------------------------------------------------------
-- Tracks (songs) -> study_materials
-- ---------------------------------------------------------------------------
WITH unit_batches AS (
    SELECT DISTINCT su.id AS unit_id, b.id AS batch_id
    FROM nest.syllabus_units su
    JOIN nest.batches b ON b.course_id = su.course_id
    WHERE NOT EXISTS (SELECT 1 FROM nest.syllabus_unit_batches sub WHERE sub.syllabus_unit_id = su.id)

    UNION

    SELECT sub.syllabus_unit_id, sub.batch_id
    FROM nest.syllabus_unit_batches sub
),
academy_admin AS (
    SELECT c.id AS course_id, (
        SELECT m.user_id
        FROM nest.academy_memberships m
        WHERE m.academy_id = c.academy_id
          AND m.role_type = 'ACADEMY_ADMIN'
          AND m.status = 'ACTIVE'
        ORDER BY m.id
        LIMIT 1
    ) AS user_id
    FROM nest.courses c
)
INSERT INTO nest.study_materials
    (batch_id, title, description, url, file_name, content_type, file_type, size_bytes,
     permission, visibility, uploaded_by, uploaded_at)
SELECT
    ub.batch_id,
    t.title,
    -- The song keeps its own title, so the unit it came from becomes context rather than a name.
    'From ' || su.title,
    t.storage_key,
    regexp_replace(t.storage_key, '^.*/', ''),
    t.content_type,
    'AUDIO',
    0,
    -- stream_only is exactly VIEW_ONLY: play it in the app, do not hand out the file.
    CASE WHEN t.stream_only THEN 'VIEW_ONLY' ELSE 'DOWNLOADABLE' END,
    'ALL',
    aa.user_id,
    now()
FROM nest.tracks t
JOIN nest.syllabus_units su ON su.id = t.syllabus_unit_id
JOIN unit_batches ub ON ub.unit_id = su.id
JOIN academy_admin aa ON aa.course_id = su.course_id
WHERE aa.user_id IS NOT NULL;

-- ---------------------------------------------------------------------------
-- What is deliberately NOT dropped
-- ---------------------------------------------------------------------------
-- syllabus_units, syllabus_unit_batches, syllabus_unit_materials and tracks all stay.
--
-- study_materials is keyed by batch, so anything attached to a course with no batches has nowhere
-- to land and is silently absent from the SELECTs above - on this database that is one file, on
-- the "yoga" course. Dropping the source tables in the same breath would destroy it with no
-- replacement, which is not something a schema migration should do quietly.
--
-- The feature is gone either way: the tile, the route and the screen are removed, so nothing reads
-- these tables any more. Dropping them is a separate, deliberate step for once the stragglers are
-- dealt with.
