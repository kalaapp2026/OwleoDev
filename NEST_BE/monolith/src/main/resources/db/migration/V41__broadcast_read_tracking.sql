-- A broadcast fans out as one in-app notification per recipient. Linking each to its broadcast lets
-- the sender's history show "Sent to 12 - 8 read" and a read rate. Broadcasts sent before this
-- migration have no linked rows and report no read figure rather than a misleading zero.
ALTER TABLE app_notifications ADD COLUMN broadcast_id UUID;
CREATE INDEX idx_app_notifications_broadcast ON app_notifications (broadcast_id) WHERE broadcast_id IS NOT NULL;
