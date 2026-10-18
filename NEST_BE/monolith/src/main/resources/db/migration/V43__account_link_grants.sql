-- Proof that a person who ALREADY has a NEST account agreed to be added to another academy.
--
-- Until now an existing account was only discovered when the creator pressed Save, which created a
-- pending membership and sent a code. The creator now confirms the person up front: the code goes to
-- the person's notifications, they read it out, and a successful check records one of these rows. The
-- registration that follows presents the row's id and is then allowed to activate the membership
-- straight away - without it, the older pending-membership path still applies.
--
-- Bound to one user, one academy and the creator who verified it, short-lived and single-use, so a
-- grant can't be carried to a different academy, a different person or someone else's session. No FK
-- constraints, same as the rest of this schema.
CREATE TABLE account_link_grants (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID        NOT NULL,
    academy_id  UUID        NOT NULL,
    created_by  UUID        NOT NULL,
    expires_at  TIMESTAMPTZ NOT NULL,
    used        BOOLEAN     NOT NULL DEFAULT FALSE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_account_link_grants_user ON account_link_grants (user_id);
