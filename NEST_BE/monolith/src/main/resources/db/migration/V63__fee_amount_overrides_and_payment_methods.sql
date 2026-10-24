-- A shared Other fee (a costume, say) normally costs every student in its batches the same. The Fees
-- screen lets an admin change what ONE student owes for it - a sibling discount, a scholarship - so
-- that amount is stored per student here and read in place of the fee type's own. The type's amount
-- is untouched, and so is everyone else's.
CREATE TABLE student_fee_type_amounts (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    academy_id    UUID          NOT NULL,
    membership_id UUID          NOT NULL,
    fee_type_id   UUID          NOT NULL REFERENCES fee_types (id) ON DELETE CASCADE,
    amount        NUMERIC(12,2) NOT NULL,
    updated_by    UUID,
    updated_at    TIMESTAMPTZ   NOT NULL DEFAULT now(),
    CONSTRAINT uq_student_fee_type_amounts UNIQUE (membership_id, fee_type_id),
    CONSTRAINT ck_student_fee_type_amounts_positive CHECK (amount > 0)
);
CREATE INDEX idx_student_fee_type_amounts_academy ON student_fee_type_amounts (academy_id);
CREATE INDEX idx_student_fee_type_amounts_type ON student_fee_type_amounts (fee_type_id);

-- Which payment methods an Other fee accepts, as a comma-separated list (e.g. 'CASH,UPI'). More than
-- one is allowed; default_mode stays as the first of them so everything that reads it keeps working.
ALTER TABLE fee_types ADD COLUMN payment_methods VARCHAR(64);
ALTER TABLE student_fees ADD COLUMN payment_methods VARCHAR(64);
UPDATE fee_types SET payment_methods = default_mode WHERE default_mode IS NOT NULL;
UPDATE student_fees SET payment_methods = default_mode WHERE default_mode IS NOT NULL;
