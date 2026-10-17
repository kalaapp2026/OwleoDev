-- Temporary batches run for exactly their start..end range, but the class generator used to lay
-- down eight weeks of classes regardless, so a one-day batch had classes on every following week.
-- The generator now stops at the batch's end date; this removes the stray ones already created.
--
-- Only untouched, auto-generated classes are removed: still SCHEDULED, created from the weekly
-- pattern (schedule_id set), not part of a reschedule, with no substitute and no attendance taken.
-- Anything a person has acted on is left alone.
DELETE FROM class_instances ci
USING batches b
WHERE ci.batch_id = b.id
  AND b.batch_type = 'TEMPORARY'
  AND b.end_date IS NOT NULL
  AND ci.date > b.end_date
  AND ci.status = 'SCHEDULED'
  AND ci.schedule_id IS NOT NULL
  AND ci.original_instance_id IS NULL
  AND ci.substitute_trainer_membership_id IS NULL
  AND NOT EXISTS (SELECT 1 FROM attendance a WHERE a.class_instance_id = ci.id);
