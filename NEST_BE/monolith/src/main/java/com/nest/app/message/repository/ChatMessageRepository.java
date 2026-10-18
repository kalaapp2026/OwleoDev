package com.nest.app.message.repository;

import com.nest.app.message.entity.ChatMessage;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.UUID;

public interface ChatMessageRepository extends JpaRepository<ChatMessage, UUID> {

    /** Newest first and capped: a thread opens on its latest messages, not its whole history. */
    List<ChatMessage> findTop200ByConversationIdOrderByCreatedAtDesc(UUID conversationId);
}
