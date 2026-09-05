-- Course Creation module: brings the courses table in line with the design spec.
--
-- Three separate changes, kept in one migration because they all land on `courses` and a course
-- created between them would be half-configured:
--   1. Category vocabulary is replaced (see the remap below).
--   2. Courses gain an icon, drawn from the app's own icon set.
--   3. Billing gains a payment-due day and the accepted payment methods, both of which the fee
--      screens already ask for but had nowhere to persist.

-- ---------------------------------------------------------------------------
-- 1. Category vocabulary
-- ---------------------------------------------------------------------------
-- The old set (DANCE / MUSIC_VOCAL / MUSIC_INSTRUMENTAL / FITNESS / OTHER) is replaced by the
-- seven disciplines the UI actually offers. The vocal/instrumental split is deliberately dropped
-- at the category level and re-expressed through icon_key below - a Carnatic vocal course and a
-- guitar course are both "Music" to a parent browsing the academy, and the icon carries the
-- distinction far better than a second category ever did. FITNESS had no home in the new set and
-- folds into OTHERS.
--
-- No CHECK constraint is added: the column is a plain VARCHAR that Hibernate maps by enum name,
-- and a constraint here would have to be dropped and rewritten on every future category added.
UPDATE courses SET category = 'MUSIC'  WHERE category IN ('MUSIC_VOCAL', 'MUSIC_INSTRUMENTAL');
UPDATE courses SET category = 'OTHERS' WHERE category IN ('FITNESS', 'OTHER');

-- ---------------------------------------------------------------------------
-- 2. Icon
-- ---------------------------------------------------------------------------
ALTER TABLE courses ADD COLUMN icon_key VARCHAR(40);

-- Backfill every existing course with its category's "whole category" icon - the same default a
-- newly created course gets before the admin picks something more specific. Leaving these NULL
-- would render a hole in every course list until each course was edited by hand.
UPDATE courses SET icon_key = CASE category
    WHEN 'DANCE'      THEN 'dance_general'
    WHEN 'MUSIC'      THEN 'music_general'
    WHEN 'FINE_ARTS'  THEN 'finearts_general'
    WHEN 'LITERATURE' THEN 'literature_general'
    WHEN 'THEATRE'    THEN 'theatre_general'
    WHEN 'FASHION'    THEN 'fashion_general'
    ELSE 'others_general'
END
WHERE icon_key IS NULL;

-- ---------------------------------------------------------------------------
-- 3. Billing
-- ---------------------------------------------------------------------------
-- Distinct from billing_day_of_month: that is the day a fee slip is GENERATED, this is the day it
-- becomes overdue. They are usually a few days apart (bill on the 5th, due on the 10th), and
-- conflating them is what made "Due" impossible to derive without guessing a grace period.
ALTER TABLE courses ADD COLUMN due_day_of_month INT;
ALTER TABLE courses ADD CONSTRAINT ck_courses_due_day
    CHECK (due_day_of_month IS NULL OR (due_day_of_month BETWEEN 1 AND 31));

-- Which methods this course's fees may be collected by, as a comma-separated set drawn from
-- CASH / UPI / GATEWAY. Stored inline rather than as a child table on purpose: the set is fixed
-- and tiny, it is only ever read as a whole alongside the course, and nothing filters courses by
-- payment method - a join table would add a query and buy nothing.
ALTER TABLE courses ADD COLUMN payment_methods VARCHAR(64) NOT NULL DEFAULT 'CASH';
