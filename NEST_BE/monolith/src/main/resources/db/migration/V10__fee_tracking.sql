-- Fee tracking: cycle-aware fee slips (a quarterly/yearly course now bills on its own cadence,
-- not every month like a monthly one) plus a per-period open/closed state so an underpaid period
-- either rolls its shortfall into the next slip (OPEN, the default) or is explicitly written off
-- ("close", CLOSED) instead of silently vanishing either way.

ALTER TABLE fee_slips
    ADD COLUMN carried_forward_amount NUMERIC(12,2) NOT NULL DEFAULT 0,
    ADD COLUMN status VARCHAR(20) NOT NULL DEFAULT 'OPEN';
