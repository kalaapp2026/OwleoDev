-- Trainer features move from flat per-membership to per-(membership, course) so a trainer can hold
-- a feature on one course and not another. Backfill preserves current access exactly: every
-- existing per-membership feature becomes a per-course grant on each course that trainer is mapped
-- to - i.e. "same features on all courses", which is the assignment UI's default toggle state.
CREATE TABLE course_feature_grants (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    membership_id UUID        NOT NULL,
    course_id     UUID        NOT NULL,
    feature_key   VARCHAR(50) NOT NULL,
    granted_by    UUID,
    created_at    TIMESTAMPTZ,
    CONSTRAINT uq_cfg_membership_course_feature UNIQUE (membership_id, course_id, feature_key)
);
CREATE INDEX idx_cfg_membership ON course_feature_grants (membership_id);

INSERT INTO course_feature_grants (membership_id, course_id, feature_key, granted_by, created_at)
SELECT fg.membership_id, cm.course_id, fg.feature_key, fg.granted_by, fg.created_at
FROM feature_grants fg
JOIN course_map cm ON cm.membership_id = fg.membership_id;
