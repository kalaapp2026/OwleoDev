-- Password reset (forgot password): the existing otp_verifications table already does everything
-- a code-based reset needs (rate limiting, expiry, attempt limiting) - it just assumed every code
-- goes to a phone. This adds an email-delivered lane alongside it rather than a parallel table.

ALTER TABLE otp_verifications ALTER COLUMN phone_hash DROP NOT NULL;
ALTER TABLE otp_verifications ADD COLUMN email_hash VARCHAR(64);

CREATE INDEX idx_otp_email_hash ON otp_verifications (email_hash);

-- A row must still be addressable by exactly one channel - never neither.
ALTER TABLE otp_verifications ADD CONSTRAINT chk_otp_verifications_has_destination
    CHECK (phone_hash IS NOT NULL OR email_hash IS NOT NULL);
