-- Notifications are now split per app-module (Social vs ERP) so each bell only shows its own kind.
-- Every existing row is a MEMBERSHIP_CONFIRMATION OTP, which belongs to the ERP (registration)
-- world, so backfill those to ERP; new rows always set it explicitly.
ALTER TABLE app_notifications ADD COLUMN module VARCHAR(20) NOT NULL DEFAULT 'ERP';
