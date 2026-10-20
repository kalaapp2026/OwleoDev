-- HQ Support: tickets from academy admins (issues, enquiries, feedback) and student fee problems.
-- HQ handles student topics about FEES only; any other student matter stays with the academy.
CREATE TABLE hq_tickets (
    id          UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    seq         BIGINT        GENERATED ALWAYS AS IDENTITY,
    kind        VARCHAR(10)   NOT NULL CHECK (kind IN ('ISSUE', 'ENQUIRY', 'FEEDBACK', 'FEE')),
    academy_id  UUID          REFERENCES academies (id) ON DELETE SET NULL,
    category    VARCHAR(60)   NOT NULL,
    priority    VARCHAR(8)    NOT NULL DEFAULT 'MEDIUM' CHECK (priority IN ('URGENT', 'HIGH', 'MEDIUM', 'LOW')),
    status      VARCHAR(10)   NOT NULL DEFAULT 'OPEN' CHECK (status IN ('OPEN', 'PROGRESS', 'WAITING', 'RESOLVED', 'CLOSED')),
    raised_by   VARCHAR(120)  NOT NULL,
    raised_role VARCHAR(30)   NOT NULL,
    subject     VARCHAR(160)  NOT NULL,
    body        VARCHAR(2000) NOT NULL,
    rating      SMALLINT      CHECK (rating BETWEEN 1 AND 5),
    amount      NUMERIC(12,2),
    assignee    VARCHAR(120),
    created_at  TIMESTAMPTZ   NOT NULL DEFAULT now(),
    resolved_at TIMESTAMPTZ
);
CREATE INDEX idx_hq_tickets_status ON hq_tickets (status, created_at DESC);
CREATE INDEX idx_hq_tickets_academy ON hq_tickets (academy_id);

CREATE TABLE hq_ticket_messages (
    id         UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    ticket_id  UUID          NOT NULL REFERENCES hq_tickets (id) ON DELETE CASCADE,
    author     VARCHAR(120)  NOT NULL,
    -- True for a reply from HQ staff, false for the person who raised it, and for system notes.
    from_hq    BOOLEAN       NOT NULL DEFAULT FALSE,
    body       VARCHAR(2000) NOT NULL,
    at         TIMESTAMPTZ   NOT NULL DEFAULT now()
);
CREATE INDEX idx_hq_ticket_messages_ticket ON hq_ticket_messages (ticket_id, at);
