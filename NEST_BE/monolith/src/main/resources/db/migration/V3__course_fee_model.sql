-- NEST Course Fee Calculation Spec §2/§3: per-course fee model (Per-Class / Fixed / Hybrid).
-- Existing courses default to FIXED, which is their current de-facto behaviour (a flat
-- default_fee regardless of attendance), so this is backwards compatible with no data migration.

ALTER TABLE courses
    ADD COLUMN fee_model VARCHAR(20) NOT NULL DEFAULT 'FIXED',
    ADD COLUMN fee_per_class NUMERIC(12,2),
    ADD COLUMN hybrid_expected_classes_per_period INT,
    ADD COLUMN hybrid_threshold_attendance INT,
    ADD COLUMN hybrid_fee_above_threshold_percent INT NOT NULL DEFAULT 100,
    ADD COLUMN hybrid_fee_below_threshold_percent INT,
    ADD COLUMN hybrid_min_fee_amount NUMERIC(12,2);

-- default_fee is now optional at the DB level (PER_CLASS courses use fee_per_class instead);
-- CourseService enforces the right field is present for whichever fee_model is chosen.
ALTER TABLE courses ALTER COLUMN default_fee DROP NOT NULL;
