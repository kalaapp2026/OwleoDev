package com.nest.app.message.dto;

import com.nest.common.security.Role;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import java.time.Instant;
import java.util.UUID;

/** Wire shapes for the Chats side of the Messages module. */
public final class ChatDtos {

    private ChatDtos() {
    }

    /** Someone the caller can chat with. {@code subtitle} is their courses, or their role if none. */
    public record ChatContact(UUID membershipId, String name, Role roleType, String subtitle) {
    }

    public record ConversationResponse(
            UUID id,
            ChatContact contact,
            String lastMessage,
            boolean lastMessageFromMe,
            Instant lastMessageAt,
            int unreadCount
    ) {
    }

    public record ChatMessageResponse(UUID id, boolean fromMe, String body, Instant createdAt) {
    }

    public record StartConversationRequest(@NotNull UUID contactMembershipId) {
    }

    public record SendChatMessageRequest(@NotBlank @Size(max = 2000) String body) {
    }
}
