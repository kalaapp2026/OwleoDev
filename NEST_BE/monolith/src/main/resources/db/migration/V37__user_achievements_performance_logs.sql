-- Student Profile module: a person's own achievements and performance log. Both belong to the
-- user (not a membership) - an award follows them across academies - and carry an optional
-- academy_id only so the performance log can be filtered to the academy being viewed.
-- No FK constraints, same as the rest of this schema.
CREATE TABLE user_achievements (
    id          UUID PRIMARY KEY,
    user_id     UUID NOT NULL,
    academy_id  UUID,
    title       VARCHAR(255) NOT NULL,
    description TEXT,
    type        VARCHAR(20) NOT NULL,
    achieved_on DATE NOT NULL,
    created_at  TIMESTAMP NOT NULL DEFAULT now()
);
CREATE INDEX idx_user_achievements_user ON user_achievements (user_id, achieved_on);

CREATE TABLE user_performance_logs (
    id         UUID PRIMARY KEY,
    user_id    UUID NOT NULL,
    academy_id UUID,
    title      VARCHAR(255) NOT NULL,
    category   VARCHAR(20) NOT NULL,
    result     VARCHAR(255) NOT NULL,
    notes      TEXT,
    logged_on  DATE NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT now()
);
CREATE INDEX idx_user_performance_logs_user ON user_performance_logs (user_id, logged_on);
