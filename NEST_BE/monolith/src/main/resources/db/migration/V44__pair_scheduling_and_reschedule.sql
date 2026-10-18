-- Scheduling the weekly time (BATCH_SCHEDULING) and moving a single class (RESCHEDULE) are one
-- permission on the trainer form now. Older grants may hold only one of the two, which left a
-- trainer able to open the Schedule screen but refused on half of it. Give each holder the other.
INSERT INTO course_feature_grants (membership_id, course_id, feature_key, granted_by, created_at)
SELECT g.membership_id, g.course_id, 'RESCHEDULE', g.granted_by, g.created_at
FROM course_feature_grants g
WHERE g.feature_key = 'BATCH_SCHEDULING'
  AND NOT EXISTS (SELECT 1 FROM course_feature_grants x
                  WHERE x.membership_id = g.membership_id AND x.course_id = g.course_id
                    AND x.feature_key = 'RESCHEDULE');

INSERT INTO course_feature_grants (membership_id, course_id, feature_key, granted_by, created_at)
SELECT g.membership_id, g.course_id, 'BATCH_SCHEDULING', g.granted_by, g.created_at
FROM course_feature_grants g
WHERE g.feature_key = 'RESCHEDULE'
  AND NOT EXISTS (SELECT 1 FROM course_feature_grants x
                  WHERE x.membership_id = g.membership_id AND x.course_id = g.course_id
                    AND x.feature_key = 'BATCH_SCHEDULING');
