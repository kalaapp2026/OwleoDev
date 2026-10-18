package com.nest.app.message.controller;

import com.nest.app.message.dto.ChatDtos.ChatContact;
import com.nest.app.message.dto.ChatDtos.ChatMessageResponse;
import com.nest.app.message.dto.ChatDtos.ConversationResponse;
import com.nest.app.message.dto.ChatDtos.SendChatMessageRequest;
import com.nest.app.message.dto.ChatDtos.StartConversationRequest;
import com.nest.app.message.service.ChatService;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.UUID;

/**
 * Chats between two people in the active academy. No {@code @RequiresFeature}: every role in an
 * academy can chat, so the gating that matters (who may start one, who may read which) lives in
 * {@link ChatService}, against the caller's own membership.
 */
@RestController
@Tag(name = "Messages")
public class ChatController {

    private final ChatService chatService;

    public ChatController(ChatService chatService) {
        this.chatService = chatService;
    }

    @GetMapping("/academies/me/conversations")
    public List<ConversationResponse> list() {
        return chatService.listConversations();
    }

    @GetMapping("/academies/me/conversations/contacts")
    public List<ChatContact> contacts() {
        return chatService.contacts();
    }

    @PostMapping("/academies/me/conversations")
    public ConversationResponse start(@Valid @RequestBody StartConversationRequest request) {
        return chatService.start(request.contactMembershipId());
    }

    @GetMapping("/academies/me/conversations/{id}/messages")
    public List<ChatMessageResponse> messages(@PathVariable UUID id) {
        return chatService.messages(id);
    }

    @PostMapping("/academies/me/conversations/{id}/messages")
    public ChatMessageResponse send(@PathVariable UUID id, @Valid @RequestBody SendChatMessageRequest request) {
        return chatService.send(id, request.body());
    }

    @PostMapping("/academies/me/conversations/{id}/read")
    public ResponseEntity<Void> markRead(@PathVariable UUID id) {
        chatService.markRead(id);
        return ResponseEntity.noContent().build();
    }
}
