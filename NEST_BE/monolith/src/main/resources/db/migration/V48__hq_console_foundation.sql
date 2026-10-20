-- Owleo HQ Console foundation: which kind of HQ staff member a platform account is, and the audit
-- trail every HQ action is written to.
--
-- Everyone who runs the HQ console has users.role_type = 'SUPER_ADMIN' (that is what the existing
-- @PreAuthorize("hasRole('SUPER_ADMIN')") endpoints check). hq_role narrows that down to what the
-- person may actually do in the console: SUPER (everything), OPS, FINANCE or SUPPORT. NULL means
-- SUPER, so the existing seeded super admin keeps full access without a data fix.
ALTER TABLE users ADD COLUMN hq_role VARCHAR(20);
ALTER TABLE users ADD CONSTRAINT chk_users_hq_role
    CHECK (hq_role IS NULL OR hq_role IN ('SUPER', 'OPS', 'FINANCE', 'SUPPORT'));

-- The "Audit trail" in Reports and the "Configuration history" in Master data. Separate from
-- audit_log, which records per-academy ERP actions keyed by membership: this one is about what
-- HQ staff did to the platform, in sentences a person can read.
CREATE TABLE hq_audit_log (
    id           UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    occurred_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
    actor_id     UUID,
    actor_name   VARCHAR(120) NOT NULL,
    actor_role   VARCHAR(20)  NOT NULL,
    -- Which console area it belongs to ('academies', 'master', 'approvals', ...), for filtering.
    area         VARCHAR(40),
    detail       VARCHAR(600) NOT NULL
);
CREATE INDEX idx_hq_audit_time ON hq_audit_log (occurred_at DESC);
CREATE INDEX idx_hq_audit_area ON hq_audit_log (area, occurred_at DESC);
