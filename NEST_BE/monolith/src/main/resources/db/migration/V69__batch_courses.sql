-- A batch can now span several courses (Basic + Intermediate + Advanced learning together, or a
-- Temporary batch that pulls students from every course for one show).
--
-- Additive on purpose, same as batch_trainers. batches.course_id stays as the batch's PRIMARY course,
-- so every query and screen that reads one course keeps working. This table lists EVERY course the
-- batch covers, the primary included, so "batches of course X" is one join rather than a column unioned
-- with a table. A batch always has at least its primary course here.
CREATE TABLE batch_courses (
    batch_id  UUID NOT NULL,
    course_id UUID NOT NULL,
    PRIMARY KEY (batch_id, course_id)
);

CREATE INDEX idx_batch_courses_course ON batch_courses (course_id);

INSERT INTO batch_courses (batch_id, course_id)
SELECT id, course_id FROM batches;
