-- Super Admin platform analytics groundwork.
--
-- last_seen_at is what makes "active now / DAU / WAU / MAU" answerable at all - nothing today
-- records that a user did anything after signing up. It's stamped on authenticated requests
-- (throttled, see ActivityTrackingFilter) rather than only at login, so someone who stays logged
-- in for weeks still counts as active on the days they actually used the app.
ALTER TABLE users ADD COLUMN last_seen_at TIMESTAMPTZ;
CREATE INDEX idx_users_last_seen ON users (last_seen_at);

-- Install counting. The backend genuinely cannot see Play Store / App Store download numbers -
-- those live in the store consoles - so this is an honest PROXY: one row per distinct device that
-- has ever launched the app. It undercounts (a reinstall on the same device is one row) and can
-- overcount (same person on phone + tablet), and the dashboard labels it "installs seen" rather
-- than "downloads" for exactly that reason.
CREATE TABLE device_installs (
    device_id    VARCHAR(128) PRIMARY KEY,
    platform     VARCHAR(20),
    app_version  VARCHAR(40),
    first_seen_at TIMESTAMPTZ NOT NULL,
    last_seen_at  TIMESTAMPTZ NOT NULL
);
CREATE INDEX idx_device_installs_first_seen ON device_installs (first_seen_at);
