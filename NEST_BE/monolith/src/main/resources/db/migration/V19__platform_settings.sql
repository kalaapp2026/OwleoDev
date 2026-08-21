-- Platform-wide settings the Super Admin controls, currently just which half of the app users see.
--
-- The product ships two worlds (ERP and Social) behind one nav toggle, but rollout focuses on ERP
-- first - showing a half-finished Social side to an academy being onboarded makes the product look
-- unfinished and invites questions nobody wants to answer yet. This lets that be switched centrally
-- rather than by rebuilding the app with a flag.
--
-- Single row by construction: the CHECK pins the id to 1, so there can never be two rows of
-- "the platform's settings" disagreeing with each other.
CREATE TABLE platform_settings (
    id         SMALLINT PRIMARY KEY DEFAULT 1 CHECK (id = 1),
    -- ERP_FIRST | SOCIAL_FIRST | ERP_ONLY | SOCIAL_ONLY.
    -- One column rather than two booleans ("which first" + "restrict to one") on purpose: two
    -- booleans permit nonsense states like "only ERP, open Social first" that the UI would then
    -- have to invent a meaning for.
    app_mode   VARCHAR(20)  NOT NULL DEFAULT 'ERP_FIRST',
    updated_at TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_by UUID
);

-- Seed the single row so readers never have to cope with an empty table.
INSERT INTO platform_settings (id, app_mode) VALUES (1, 'ERP_FIRST');
