-- One-to-one chats (V45) were removed from the Messages module before anyone relied on them:
-- Messages is broadcast-only. V45 stays as written because it has already been applied; this
-- drops what it created. chat_messages first - it references conversations.
DROP TABLE IF EXISTS chat_messages;
DROP TABLE IF EXISTS conversations;
