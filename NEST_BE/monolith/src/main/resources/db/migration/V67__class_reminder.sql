-- When someone last pressed "Remind" on a class from the Dashboard. Lets the card say "Reminded 4:05 PM"
-- and lets the server refuse a second blast a few minutes after the first, so a double tap (or two
-- admins) cannot send the whole batch the same push twice.
ALTER TABLE class_instances ADD COLUMN last_reminder_at TIMESTAMP;
