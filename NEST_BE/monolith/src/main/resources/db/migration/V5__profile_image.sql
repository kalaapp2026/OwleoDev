-- Attendance module needs a face to show the Trainer while marking, not just a membership ID.
ALTER TABLE users ADD COLUMN profile_image_url VARCHAR(500);
