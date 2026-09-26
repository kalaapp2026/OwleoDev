-- Reference-parity additions to Event Creation: a real end date/time for multi-day events, a
-- Google Maps link alongside the free-text venue, an optional interest deadline, a
-- draft/published/cancelled status (mirroring BatchStatus/CourseStatus), and audience-targeting
-- metadata. Audience targeting is deliberately metadata only - it drives a real "N invited" count
-- and an audience badge, but does not filter who can see an event in their list, which stays
-- whole-academy as it is today.
ALTER TABLE events
    ADD COLUMN end_date TIMESTAMP,
    ADD COLUMN venue_maps_url VARCHAR(500),
    ADD COLUMN interest_deadline DATE,
    ADD COLUMN status VARCHAR(20) NOT NULL DEFAULT 'PUBLISHED',
    ADD COLUMN audience_type VARCHAR(20) NOT NULL DEFAULT 'ALL_STUDENTS',
    -- Whether the auto-publish-to-Social-post step (PRD 3.12) has already fired for this event -
    -- without this, toggling PUBLISHED -> CANCELLED -> PUBLISHED would post to Social twice.
    ADD COLUMN post_published BOOLEAN NOT NULL DEFAULT FALSE;

-- Same shape as academy_highlight_trainers (V9): composite PK, index on the owning id, no FK -
-- this schema doesn't use FK constraints anywhere.
CREATE TABLE event_course_ids (event_id UUID NOT NULL, course_id UUID NOT NULL, PRIMARY KEY (event_id, course_id));
CREATE INDEX idx_event_course_ids_event ON event_course_ids (event_id);

CREATE TABLE event_batch_ids (event_id UUID NOT NULL, batch_id UUID NOT NULL, PRIMARY KEY (event_id, batch_id));
CREATE INDEX idx_event_batch_ids_event ON event_batch_ids (event_id);

CREATE TABLE event_individual_ids (event_id UUID NOT NULL, membership_id UUID NOT NULL, PRIMARY KEY (event_id, membership_id));
CREATE INDEX idx_event_individual_ids_event ON event_individual_ids (event_id);
