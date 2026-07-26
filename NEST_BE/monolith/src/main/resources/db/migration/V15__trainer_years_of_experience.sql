-- Trainer registration gains a fuller profile (dob/address/city/state, matching what students
-- already collect) plus a trainer-specific field with nothing else to attach it to.
ALTER TABLE users ADD COLUMN years_of_experience INTEGER;
