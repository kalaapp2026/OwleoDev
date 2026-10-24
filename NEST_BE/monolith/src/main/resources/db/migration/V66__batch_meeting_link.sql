-- An online (or hybrid) batch meets on a Google Meet / Zoom / Teams call. The admin pastes the link
-- once on the batch; students and trainers get a Join button on each class instead of the link being
-- sent over WhatsApp every time. NULL for a batch that meets in person.
ALTER TABLE batches ADD COLUMN meeting_link VARCHAR(500);
