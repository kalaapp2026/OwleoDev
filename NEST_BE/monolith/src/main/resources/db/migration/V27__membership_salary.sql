-- Trainer salary, as collected by the trainer registration form.
--
-- On the membership rather than the user, for the same reason joining_date is (V26): the same
-- person can teach at two academies for two different amounts, and a column on `users` would let
-- one academy read what the other pays.
--
-- Nullable with no default. Zero is a meaningful salary; "not recorded" is a different statement
-- and the form leaves the field optional, so the absence has to be representable.
ALTER TABLE academy_memberships ADD COLUMN salary NUMERIC(12, 2);
