-- The Messages module (PRD-adjacent - matches the reference bundle's Messages tile): a real
-- broadcast composer for Academy Admin, built on the existing notification infrastructure. One
-- row per compose action; the audience actually notified is fanned out as individual
-- app_notifications rows at send time and is not re-derived from this table afterward.
CREATE TABLE academy_broadcasts (
    id              UUID PRIMARY KEY,
    academy_id      UUID NOT NULL,
    title           VARCHAR(255) NOT NULL,
    body            TEXT NOT NULL,
    audience_type   VARCHAR(20) NOT NULL,
    recipient_count INTEGER NOT NULL,
    created_by      UUID NOT NULL,
    created_at      TIMESTAMP NOT NULL DEFAULT now()
);
CREATE INDEX idx_academy_broadcasts_academy ON academy_broadcasts (academy_id, created_at);

-- Same shape as event_course_ids/event_batch_ids/event_individual_ids (V31) - composite PK, index
-- on the owning id, no FK constraints anywhere in this schema.
CREATE TABLE academy_broadcast_course_ids (broadcast_id UUID NOT NULL, course_id UUID NOT NULL, PRIMARY KEY (broadcast_id, course_id));
CREATE INDEX idx_academy_broadcast_course_ids_broadcast ON academy_broadcast_course_ids (broadcast_id);

CREATE TABLE academy_broadcast_batch_ids (broadcast_id UUID NOT NULL, batch_id UUID NOT NULL, PRIMARY KEY (broadcast_id, batch_id));
CREATE INDEX idx_academy_broadcast_batch_ids_broadcast ON academy_broadcast_batch_ids (broadcast_id);

CREATE TABLE academy_broadcast_individual_ids (broadcast_id UUID NOT NULL, membership_id UUID NOT NULL, PRIMARY KEY (broadcast_id, membership_id));
CREATE INDEX idx_academy_broadcast_individual_ids_broadcast ON academy_broadcast_individual_ids (broadcast_id);
