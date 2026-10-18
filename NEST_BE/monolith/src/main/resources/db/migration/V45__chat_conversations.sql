-- One-to-one chats between two memberships of the same academy. A pair has exactly one
-- conversation, stored with the lower membership id first so (A,B) and (B,A) cannot both exist.
-- Unread is a counter per side rather than a count over messages: the chat list needs it for every
-- row, and a counter is one column read instead of one query per conversation.
CREATE TABLE conversations (
    id                 UUID        PRIMARY KEY,
    academy_id         UUID        NOT NULL,
    member_low_id      UUID        NOT NULL,
    member_high_id     UUID        NOT NULL,
    low_unread         INTEGER     NOT NULL DEFAULT 0,
    high_unread        INTEGER     NOT NULL DEFAULT 0,
    last_message_body  TEXT,
    last_sender_id     UUID,
    last_message_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_conversation_pair UNIQUE (academy_id, member_low_id, member_high_id),
    CONSTRAINT ck_conversation_distinct CHECK (member_low_id <> member_high_id)
);
CREATE INDEX idx_conversations_low  ON conversations (academy_id, member_low_id,  last_message_at DESC);
CREATE INDEX idx_conversations_high ON conversations (academy_id, member_high_id, last_message_at DESC);

CREATE TABLE chat_messages (
    id                  UUID        PRIMARY KEY,
    conversation_id     UUID        NOT NULL REFERENCES conversations (id) ON DELETE CASCADE,
    sender_membership_id UUID       NOT NULL,
    body                TEXT        NOT NULL,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_chat_messages_conversation ON chat_messages (conversation_id, created_at);
