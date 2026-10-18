package com.nest.app.message.service;

import com.nest.app.curriculum.entity.Course;
import com.nest.app.curriculum.repository.CourseRepository;
import com.nest.app.identity.entity.AcademyMembership;
import com.nest.app.identity.entity.CourseMap;
import com.nest.app.identity.entity.MembershipStatus;
import com.nest.app.identity.entity.User;
import com.nest.app.identity.repository.AcademyMembershipRepository;
import com.nest.app.identity.repository.CourseMapRepository;
import com.nest.app.identity.repository.UserRepository;
import com.nest.app.message.dto.ChatDtos.ChatContact;
import com.nest.app.message.dto.ChatDtos.ChatMessageResponse;
import com.nest.app.message.dto.ChatDtos.ConversationResponse;
import com.nest.app.message.entity.ChatMessage;
import com.nest.app.message.entity.Conversation;
import com.nest.app.message.repository.ChatMessageRepository;
import com.nest.app.message.repository.ConversationRepository;
import com.nest.common.exception.ForbiddenException;
import com.nest.common.exception.ResourceNotFoundException;
import com.nest.common.security.Role;
import com.nest.common.security.TenantContext;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.util.ArrayList;
import java.util.Collection;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;

/**
 * One-to-one chats inside an academy. A conversation is between two memberships, so someone who
 * is a student at one academy and a trainer at another has separate chats for each.
 *
 * <p>Who may start a chat: an Academy Admin can message anyone active in the academy; everyone
 * else can only message an Academy Admin. Replying is always allowed to the other participant.
 * Every read and write is checked against the caller's own membership - a conversation id that
 * is not theirs is a 404, not a 403, so ids do not confirm that someone else's chat exists.
 */
@Service
public class ChatService {

    private final ConversationRepository conversationRepository;
    private final ChatMessageRepository messageRepository;
    private final AcademyMembershipRepository membershipRepository;
    private final UserRepository userRepository;
    private final CourseMapRepository courseMapRepository;
    private final CourseRepository courseRepository;

    public ChatService(ConversationRepository conversationRepository, ChatMessageRepository messageRepository,
                       AcademyMembershipRepository membershipRepository, UserRepository userRepository,
                       CourseMapRepository courseMapRepository, CourseRepository courseRepository) {
        this.conversationRepository = conversationRepository;
        this.messageRepository = messageRepository;
        this.membershipRepository = membershipRepository;
        this.userRepository = userRepository;
        this.courseMapRepository = courseMapRepository;
        this.courseRepository = courseRepository;
    }

    @Transactional(readOnly = true)
    public List<ConversationResponse> listConversations() {
        UUID me = TenantContext.currentMembershipId();
        List<Conversation> conversations = conversationRepository.findForMember(TenantContext.currentAcademyId(), me);
        Map<UUID, ChatContact> contacts = contactsById(conversations.stream().map(c -> c.otherThan(me)).collect(Collectors.toSet()));
        List<ConversationResponse> rows = new ArrayList<>();
        for (Conversation c : conversations) {
            ChatContact contact = contacts.get(c.otherThan(me));
            if (contact != null) {
                rows.add(toResponse(c, me, contact));
            }
        }
        return rows;
    }

    /** People the caller may start a chat with, by name. */
    @Transactional(readOnly = true)
    public List<ChatContact> contacts() {
        MembershipScope scope = scope();
        List<AcademyMembership> candidates = scope.isAdmin()
                ? membershipRepository.findByAcademyId(scope.academyId())
                : membershipRepository.findByAcademyIdAndRoleTypeAndStatus(scope.academyId(), Role.ACADEMY_ADMIN, MembershipStatus.ACTIVE);
        Set<UUID> ids = candidates.stream()
                .filter(m -> m.getStatus() == MembershipStatus.ACTIVE && !m.getId().equals(scope.me()))
                .map(AcademyMembership::getId).collect(Collectors.toSet());
        return contactsById(ids).values().stream()
                .sorted(Comparator.comparing((ChatContact c) -> c.roleType() == Role.TRAINER ? 0 : 1)
                        .thenComparing(c -> c.name().toLowerCase()))
                .toList();
    }

    /** Opens the chat with {@code contactMembershipId}, creating it if this is the first time. */
    @Transactional
    public ConversationResponse start(UUID contactMembershipId) {
        MembershipScope scope = scope();
        if (contactMembershipId.equals(scope.me())) {
            throw new ForbiddenException("You cannot message yourself.");
        }
        AcademyMembership contact = membershipRepository.findById(contactMembershipId)
                .filter(m -> scope.academyId().equals(m.getAcademyId()) && m.getStatus() == MembershipStatus.ACTIVE)
                .orElseThrow(() -> new ResourceNotFoundException("Person not found: " + contactMembershipId));
        if (!scope.isAdmin() && contact.getRoleType() != Role.ACADEMY_ADMIN) {
            throw new ForbiddenException("You can only start a chat with an Academy Admin.");
        }

        UUID[] pair = Conversation.orderedPair(scope.me(), contactMembershipId);
        Conversation conversation = conversationRepository
                .findByAcademyIdAndMemberLowIdAndMemberHighId(scope.academyId(), pair[0], pair[1])
                .orElseGet(() -> conversationRepository.save(Conversation.builder()
                        .academyId(scope.academyId()).memberLowId(pair[0]).memberHighId(pair[1])
                        .lastMessageAt(Instant.now()).build()));
        ChatContact chatContact = contactsById(Set.of(contactMembershipId)).get(contactMembershipId);
        return toResponse(conversation, scope.me(), chatContact);
    }

    @Transactional(readOnly = true)
    public List<ChatMessageResponse> messages(UUID conversationId) {
        UUID me = TenantContext.currentMembershipId();
        Conversation conversation = participantConversation(conversationId, me);
        List<ChatMessage> newestFirst = messageRepository.findTop200ByConversationIdOrderByCreatedAtDesc(conversation.getId());
        List<ChatMessageResponse> oldestFirst = new ArrayList<>(newestFirst.size());
        for (int i = newestFirst.size() - 1; i >= 0; i--) {
            oldestFirst.add(toResponse(newestFirst.get(i), me));
        }
        return oldestFirst;
    }

    @Transactional
    public ChatMessageResponse send(UUID conversationId, String body) {
        UUID me = TenantContext.currentMembershipId();
        Conversation conversation = participantConversation(conversationId, me);
        UUID other = conversation.otherThan(me);
        boolean otherActive = membershipRepository.findById(other)
                .map(m -> m.getStatus() == MembershipStatus.ACTIVE).orElse(false);
        if (!otherActive) {
            throw new ForbiddenException("This person is no longer active in the academy.");
        }

        String text = body.trim();
        ChatMessage saved = messageRepository.save(ChatMessage.builder()
                .conversationId(conversation.getId()).senderMembershipId(me).body(text).build());
        boolean meIsLow = conversation.getMemberLowId().equals(me);
        conversationRepository.recordMessage(conversation.getId(), text, me, Instant.now(),
                meIsLow ? 0 : 1, meIsLow ? 1 : 0);
        return toResponse(saved, me);
    }

    @Transactional
    public void markRead(UUID conversationId) {
        UUID me = TenantContext.currentMembershipId();
        Conversation conversation = participantConversation(conversationId, me);
        if (conversation.getMemberLowId().equals(me)) {
            conversationRepository.clearLowUnread(conversation.getId());
        } else {
            conversationRepository.clearHighUnread(conversation.getId());
        }
    }

    private Conversation participantConversation(UUID conversationId, UUID me) {
        return conversationRepository.findById(conversationId)
                .filter(c -> c.includes(me) && c.getAcademyId().equals(TenantContext.currentAcademyId()))
                .orElseThrow(() -> new ResourceNotFoundException("Conversation not found: " + conversationId));
    }

    private MembershipScope scope() {
        var membership = TenantContext.currentMembership();
        return new MembershipScope(membership.academyId(), TenantContext.currentMembershipId(),
                membership.roleType() == Role.ACADEMY_ADMIN);
    }

    private record MembershipScope(UUID academyId, UUID me, boolean isAdmin) {
    }

    /** Name and subtitle for a set of memberships - batched, so a list of N chats is a handful of queries. */
    private Map<UUID, ChatContact> contactsById(Collection<UUID> membershipIds) {
        if (membershipIds.isEmpty()) {
            return Map.of();
        }
        List<AcademyMembership> memberships = membershipRepository.findAllById(membershipIds);
        Map<UUID, User> users = userRepository.findAllById(
                memberships.stream().map(AcademyMembership::getUserId).collect(Collectors.toSet()))
                .stream().collect(Collectors.toMap(User::getId, u -> u));

        // Courses only matter for students and trainers; an admin is just "Academy Admin".
        Set<UUID> courseBearing = memberships.stream().filter(m -> m.getRoleType() != Role.ACADEMY_ADMIN)
                .map(AcademyMembership::getId).collect(Collectors.toSet());
        Map<UUID, List<UUID>> courseIdsByMembership = new HashMap<>();
        if (!courseBearing.isEmpty()) {
            for (CourseMap map : courseMapRepository.findByMembershipIdIn(courseBearing)) {
                if (!map.isActive()) {
                    continue;
                }
                courseIdsByMembership.computeIfAbsent(map.getMembershipId(), k -> new ArrayList<>()).add(map.getCourseId());
            }
        }
        Map<UUID, String> courseNames = courseRepository
                .findAllById(courseIdsByMembership.values().stream().flatMap(List::stream).collect(Collectors.toSet()))
                .stream().collect(Collectors.toMap(Course::getId, Course::getName));

        Map<UUID, ChatContact> result = new HashMap<>();
        for (AcademyMembership m : memberships) {
            User user = users.get(m.getUserId());
            if (user == null) {
                continue;
            }
            String courses = courseIdsByMembership.getOrDefault(m.getId(), List.of()).stream()
                    .map(courseNames::get).filter(n -> n != null).sorted().collect(Collectors.joining(", "));
            result.put(m.getId(), new ChatContact(m.getId(), displayName(user), m.getRoleType(),
                    courses.isEmpty() ? roleLabel(m.getRoleType()) : courses));
        }
        return result;
    }

    private static String displayName(User user) {
        return user.getFullName() != null && !user.getFullName().isBlank() ? user.getFullName() : user.getUsername();
    }

    private static String roleLabel(Role role) {
        return switch (role) {
            case ACADEMY_ADMIN -> "Academy Admin";
            case TRAINER -> "Trainer";
            case STUDENT -> "Student";
            default -> role.name();
        };
    }

    private ConversationResponse toResponse(Conversation c, UUID me, ChatContact contact) {
        return new ConversationResponse(c.getId(), contact, c.getLastMessageBody(),
                me.equals(c.getLastSenderId()), c.getLastMessageAt(), c.unreadFor(me));
    }

    private ChatMessageResponse toResponse(ChatMessage m, UUID me) {
        return new ChatMessageResponse(m.getId(), m.getSenderMembershipId().equals(me), m.getBody(), m.getCreatedAt());
    }
}
