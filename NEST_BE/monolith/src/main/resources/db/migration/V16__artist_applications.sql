-- Guest self-signup (PRD 7.4 addendum): anyone can create a Guest account from the login screen.
-- A Guest who wants to post applies to become an Artist; Super Admin approves/rejects. Approval
-- flips users.role_type to ARTIST directly - this table is the request/decision record, not the
-- source of truth for who currently IS an artist.
CREATE TABLE artist_applications (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID        NOT NULL,
    status      VARCHAR(20) NOT NULL DEFAULT 'PENDING',
    decided_by  UUID,
    decided_at  TIMESTAMPTZ,
    created_at  TIMESTAMPTZ
);
CREATE INDEX idx_artist_applications_user ON artist_applications (user_id);
CREATE INDEX idx_artist_applications_status ON artist_applications (status);
