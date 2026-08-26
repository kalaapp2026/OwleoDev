-- Fees module, part 1: turn fee_transactions into the single ledger for BOTH fee categories, and
-- add the "Other Fees" catalogue that the second half of the module hangs off.
--
-- fee_transactions already had the important half of this right: one row per payment, never
-- updated, with the balance computed at read time as SUM(). This migration keeps that property
-- and makes it enforceable, rather than introducing a second parallel ledger - a UNION of two
-- tables is exactly what the combined statement and all-transactions screens would have had to
-- pay for on every read.
--
-- Three things change:
--   1. Tenant scoping becomes explicit (academy_id on every row, not inferred through membership).
--   2. Undo becomes a compensating row that points at what it reverses, never a DELETE.
--   3. The ledger learns to carry an "Other" fee as well as a course fee.

-- ============================= Other Fees catalogue =============================

-- A named charge an academy raises outside the regular course fee: costume, exam, annual day.
--
-- Scoped to the academy, not shared platform-wide. Two academies both having a "Costume Fee" is
-- the expected case, and they are unrelated rows with unrelated amounts - so the uniqueness that
-- matters is (academy_id, name), never name alone.
CREATE TABLE fee_types (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    academy_id   UUID          NOT NULL,
    name         VARCHAR(120)  NOT NULL,
    amount       NUMERIC(12,2) NOT NULL,
    -- Drives the derived "due" status: an unpaid fee past this date reads as overdue. Nullable
    -- because an open-ended fee (a shop purchase, say) has no last date to pay.
    due_date     DATE,
    -- Pre-selects the payment mode in the recorder. A convenience default, not a restriction.
    default_mode VARCHAR(20),
    -- Soft-retire rather than delete: a fee type with ledger history against it must keep
    -- resolving to a name, or every past transaction row loses its label.
    active       BOOLEAN       NOT NULL DEFAULT TRUE,
    created_by   UUID,
    created_at   TIMESTAMPTZ   NOT NULL DEFAULT now(),
    CONSTRAINT uq_fee_types_academy_name UNIQUE (academy_id, name),
    CONSTRAINT ck_fee_types_amount_positive CHECK (amount > 0)
);
CREATE INDEX idx_fee_types_academy ON fee_types (academy_id);

-- Which batches a fee type applies to. A costume fee usually hits several batches at once, and
-- the UI auto-selects the batch when a type is bound to exactly one - hence a join table rather
-- than a single batch_id column.
CREATE TABLE fee_type_batches (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    fee_type_id UUID NOT NULL REFERENCES fee_types (id) ON DELETE CASCADE,
    batch_id    UUID NOT NULL,
    CONSTRAINT uq_fee_type_batches UNIQUE (fee_type_id, batch_id)
);
CREATE INDEX idx_fee_type_batches_batch ON fee_type_batches (batch_id);

-- A one-off charge raised against a single named student, not a batch. Distinct from fee_types:
-- there is no catalogue entry and no batch binding, it exists only for this one person.
--
-- academy_id is stored here rather than reached through membership_id on purpose. This is the
-- table most likely to leak across tenants - it is the only fee record keyed solely by student -
-- so the tenant filter has to be a column the query can index and the API can assert on directly.
CREATE TABLE student_fees (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    academy_id    UUID          NOT NULL,
    membership_id UUID          NOT NULL,
    name          VARCHAR(120)  NOT NULL,
    amount        NUMERIC(12,2) NOT NULL,
    due_date      DATE,
    default_mode  VARCHAR(20),
    note          VARCHAR(500),
    created_by    UUID,
    created_at    TIMESTAMPTZ   NOT NULL DEFAULT now(),
    CONSTRAINT ck_student_fees_amount_positive CHECK (amount > 0)
);
CREATE INDEX idx_student_fees_academy ON student_fees (academy_id);
CREATE INDEX idx_student_fees_membership ON student_fees (membership_id);

-- ============================= the ledger =============================

ALTER TABLE fee_transactions
    ADD COLUMN academy_id                 UUID,
    ADD COLUMN category                   VARCHAR(10) NOT NULL DEFAULT 'REGULAR',
    ADD COLUMN fee_type_id                UUID REFERENCES fee_types (id),
    ADD COLUMN student_fee_id             UUID REFERENCES student_fees (id),
    -- The reversing row points at the row it cancels. The original is never touched: undoing a
    -- payment must leave evidence that it happened and was undone, not erase the fact.
    ADD COLUMN reversal_of_transaction_id UUID REFERENCES fee_transactions (id),
    ADD COLUMN reversal_reason            VARCHAR(500),
    -- The date money actually changed hands, which is not always the date it was keyed in. The
    -- received-date filter and the day grouping on the statement both read this, so a payment
    -- entered on Monday for cash taken on Saturday files under Saturday.
    ADD COLUMN occurred_on                DATE;

-- Backfill before tightening. Existing rows are all regular course fees, and their academy is
-- whichever academy the membership belongs to.
UPDATE fee_transactions t
SET academy_id = m.academy_id
FROM academy_memberships m
WHERE m.id = t.membership_id
  AND t.academy_id IS NULL;

UPDATE fee_transactions
SET occurred_on = COALESCE(created_at::date, CURRENT_DATE)
WHERE occurred_on IS NULL;

-- A transaction whose membership no longer exists cannot be tenant-scoped, and an un-scoped row
-- in a multi-tenant ledger is worse than no row: it would appear in whichever academy's query ran
-- without a filter. There should be none of these, so fail the migration loudly rather than
-- silently dropping or guessing.
DO $$
DECLARE orphan_count INTEGER;
BEGIN
    SELECT count(*) INTO orphan_count FROM fee_transactions WHERE academy_id IS NULL;
    IF orphan_count > 0 THEN
        RAISE EXCEPTION 'V21: % fee_transactions rows have no resolvable academy (membership missing). Resolve these before migrating.', orphan_count;
    END IF;
END $$;

ALTER TABLE fee_transactions
    ALTER COLUMN academy_id SET NOT NULL,
    ALTER COLUMN occurred_on SET NOT NULL;

-- An Other fee has no course and no billing period, so these can no longer be mandatory. The
-- check constraint below is what keeps them mandatory for the rows that do need them.
ALTER TABLE fee_transactions
    ALTER COLUMN course_id DROP NOT NULL,
    ALTER COLUMN period DROP NOT NULL;

-- Each category carries a different set of keys, and a row that satisfies neither shape is a bug
-- that would surface much later as a transaction belonging to nothing.
ALTER TABLE fee_transactions
    ADD CONSTRAINT ck_fee_tx_category_shape CHECK (
        (category = 'REGULAR'
            AND course_id IS NOT NULL AND period IS NOT NULL
            AND fee_type_id IS NULL AND student_fee_id IS NULL)
        OR
        (category = 'OTHER'
            AND course_id IS NULL AND period IS NULL
            -- Exactly one: a shared catalogue fee or a per-student one-off, never both.
            AND (fee_type_id IS NOT NULL) <> (student_fee_id IS NOT NULL))
    );

-- Sign carries the meaning: a payment adds, a reversal subtracts, and the balance is the sum. A
-- positive reversal or a negative payment would make SUM() quietly wrong.
ALTER TABLE fee_transactions
    ADD CONSTRAINT ck_fee_tx_reversal_sign CHECK (
        (reversal_of_transaction_id IS NULL AND amount_paid > 0)
        OR (reversal_of_transaction_id IS NOT NULL AND amount_paid < 0)
    );

-- A transaction can be reversed once. Without this, a double-tapped undo posts two compensating
-- rows and the student's balance goes negative by the payment amount.
CREATE UNIQUE INDEX uq_fee_tx_one_reversal_per_transaction
    ON fee_transactions (reversal_of_transaction_id)
    WHERE reversal_of_transaction_id IS NOT NULL;

CREATE INDEX idx_fee_tx_academy ON fee_transactions (academy_id);
-- The all-transactions screen filters by academy and month and sorts by date; the statement
-- screen does the same for one student.
CREATE INDEX idx_fee_tx_academy_occurred ON fee_transactions (academy_id, occurred_on DESC);
CREATE INDEX idx_fee_tx_fee_type ON fee_transactions (fee_type_id) WHERE fee_type_id IS NOT NULL;
CREATE INDEX idx_fee_tx_student_fee ON fee_transactions (student_fee_id) WHERE student_fee_id IS NOT NULL;

-- Insert-only, enforced by the database rather than by convention.
--
-- The balance is SUM(amount_paid) over these rows and is never stored anywhere. That is only
-- trustworthy if history cannot be rewritten - one UPDATE to an old amount silently changes every
-- balance, statement and report that has ever been derived from it, with nothing to show it
-- happened. Corrections go in as new rows.
--
-- This deliberately also blocks well-meant manual fixes. A genuine data repair means dropping the
-- trigger in a migration, making the change, and putting it back, so the repair is recorded in
-- version control like any other schema change.
CREATE OR REPLACE FUNCTION fee_transactions_append_only() RETURNS TRIGGER AS $$
BEGIN
    RAISE EXCEPTION 'fee_transactions is append-only: % is not permitted. Post a reversing transaction instead.', TG_OP;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_fee_transactions_append_only
    BEFORE UPDATE OR DELETE ON fee_transactions
    FOR EACH ROW EXECUTE FUNCTION fee_transactions_append_only();
