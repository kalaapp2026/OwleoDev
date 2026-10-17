-- Super Admin-configurable notification templates. One template per catalogued event (the catalog
-- lives in code - NotificationEvent - because each event needs a call site that fires it); the
-- row holds the wording and which channels it goes out on. No template, or enabled = false, means
-- the event stays silent. No FK constraints, like the rest of this schema.
CREATE TABLE notification_templates (
    id                     UUID PRIMARY KEY,
    event_key              VARCHAR(60)   NOT NULL UNIQUE,
    title_template         VARCHAR(200)  NOT NULL,
    body_template          VARCHAR(1000) NOT NULL,
    in_app_enabled         BOOLEAN       NOT NULL DEFAULT TRUE,
    push_enabled           BOOLEAN       NOT NULL DEFAULT FALSE,
    whatsapp_enabled       BOOLEAN       NOT NULL DEFAULT FALSE,
    -- Name of the template pre-approved in Meta Business Manager; WhatsApp business-initiated
    -- messages cannot be free text.
    whatsapp_template_name VARCHAR(120),
    enabled                BOOLEAN       NOT NULL DEFAULT TRUE,
    updated_by             UUID,
    created_at             TIMESTAMP     NOT NULL DEFAULT now(),
    updated_at             TIMESTAMP     NOT NULL DEFAULT now()
);

-- FCM registration tokens. A person can be signed in on several devices, so many rows per user.
CREATE TABLE push_device_tokens (
    id           UUID PRIMARY KEY,
    user_id      UUID         NOT NULL,
    token        VARCHAR(512) NOT NULL UNIQUE,
    platform     VARCHAR(20),
    last_seen_at TIMESTAMP    NOT NULL DEFAULT now()
);
CREATE INDEX idx_push_device_tokens_user ON push_device_tokens (user_id);

-- Delivery log for the external channels (and the in-app copy), so "why didn't I get it?" has an
-- answer the Super Admin can read.
CREATE TABLE notification_deliveries (
    id         UUID PRIMARY KEY,
    user_id    UUID        NOT NULL,
    event_key  VARCHAR(60) NOT NULL,
    channel    VARCHAR(20) NOT NULL,
    status     VARCHAR(20) NOT NULL,
    detail     VARCHAR(500),
    created_at TIMESTAMP   NOT NULL DEFAULT now()
);
CREATE INDEX idx_notification_deliveries_created ON notification_deliveries (created_at DESC);
