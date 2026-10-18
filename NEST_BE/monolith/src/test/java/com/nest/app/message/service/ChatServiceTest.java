package com.nest.app.message.service;

import com.nest.app.curriculum.repository.CourseRepository;
import com.nest.app.identity.entity.AcademyMembership;
import com.nest.app.identity.entity.MembershipStatus;
import com.nest.app.identity.entity.User;
import com.nest.app.identity.repository.AcademyMembershipRepository;
import com.nest.app.identity.repository.CourseMapRepository;
import com.nest.app.identity.repository.UserRepository;
import com.nest.app.message.entity.ChatMessage;
import com.nest.app.message.entity.Conversation;
import com.nest.app.message.repository.ChatMessageRepository;
import com.nest.app.message.repository.ConversationRepository;
import com.nest.common.exception.ForbiddenException;
import com.nest.common.exception.ResourceNotFoundException;
import com.nest.common.security.MembershipClaim;
import com.nest.common.security.NestPrincipal;
import com.nest.common.security.Role;
import com.nest.common.security.TenantContext;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/** Chats are between two memberships; only those two may read or write, and only an Academy Admin
 * can open a chat with someone who is not an Academy Admin. */
@ExtendWith(MockitoExtension.class)
class ChatServiceTest {

    @Mock
    private ConversationRepository conversationRepository;
    @Mock
    private ChatMessageRepository messageRepository;
    @Mock
    private AcademyMembershipRepository membershipRepository;
    @Mock
    private UserRepository userRepository;
    @Mock
    private CourseMapRepository courseMapRepository;
    @Mock
    private CourseRepository courseRepository;

    private ChatService chatService;
    private final UUID academyId = UUID.randomUUID();
    private final UUID me = UUID.randomUUID();

    @BeforeEach
    void setUp() {
        chatService = new ChatService(conversationRepository, messageRepository, membershipRepository,
                userRepository, courseMapRepository, courseRepository);
        lenient().when(conversationRepository.save(any(Conversation.class))).thenAnswer(inv -> {
            Conversation c = inv.getArgument(0);
            c.setId(UUID.randomUUID());
            return c;
        });
        lenient().when(messageRepository.save(any(ChatMessage.class))).thenAnswer(inv -> {
            ChatMessage m = inv.getArgument(0);
            m.setId(UUID.randomUUID());
            m.setCreatedAt(Instant.now());
            return m;
        });
    }

    @AfterEach
    void tearDown() {
        TenantContext.clear();
    }

    private void actingAs(Role role) {
        MembershipClaim claim = new MembershipClaim(me, academyId, "Natyalaya", role, Set.of(), Set.of());
        TenantContext.set(new NestPrincipal(UUID.randomUUID(), "someone", role, List.of(claim), me));
    }

    private AcademyMembership member(UUID id, Role role, MembershipStatus status, UUID academy) {
        return AcademyMembership.builder().id(id).userId(UUID.randomUUID()).academyId(academy).roleType(role).status(status).build();
    }

    private Conversation conversationBetween(UUID a, UUID b) {
        UUID[] pair = Conversation.orderedPair(a, b);
        return Conversation.builder().id(UUID.randomUUID()).academyId(academyId)
                .memberLowId(pair[0]).memberHighId(pair[1]).lastMessageAt(Instant.now()).build();
    }

    @Test
    void aStudentCannotStartAChatWithAnotherStudent() {
        actingAs(Role.STUDENT);
        UUID other = UUID.randomUUID();
        when(membershipRepository.findById(other)).thenReturn(Optional.of(member(other, Role.STUDENT, MembershipStatus.ACTIVE, academyId)));

        assertThatThrownBy(() -> chatService.start(other)).isInstanceOf(ForbiddenException.class);
        verify(conversationRepository, never()).save(any());
    }

    @Test
    void aStudentCanStartAChatWithAnAdmin() {
        actingAs(Role.STUDENT);
        UUID admin = UUID.randomUUID();
        AcademyMembership adminMembership = member(admin, Role.ACADEMY_ADMIN, MembershipStatus.ACTIVE, academyId);
        when(membershipRepository.findById(admin)).thenReturn(Optional.of(adminMembership));
        when(conversationRepository.findByAcademyIdAndMemberLowIdAndMemberHighId(eq(academyId), any(), any()))
                .thenReturn(Optional.empty());
        when(membershipRepository.findAllById(Set.of(admin))).thenReturn(List.of(adminMembership));
        when(userRepository.findAllById(any())).thenReturn(List.of(User.builder().id(adminMembership.getUserId()).fullName("Meera").build()));

        var response = chatService.start(admin);

        assertThat(response.contact().name()).isEqualTo("Meera");
        verify(conversationRepository).save(any(Conversation.class));
    }

    @Test
    void anAdminCannotReachSomeoneInAnotherAcademy() {
        actingAs(Role.ACADEMY_ADMIN);
        UUID foreign = UUID.randomUUID();
        when(membershipRepository.findById(foreign)).thenReturn(Optional.of(member(foreign, Role.STUDENT, MembershipStatus.ACTIVE, UUID.randomUUID())));

        assertThatThrownBy(() -> chatService.start(foreign)).isInstanceOf(ResourceNotFoundException.class);
    }

    @Test
    void startingAChatWithYourselfIsRefused() {
        actingAs(Role.ACADEMY_ADMIN);
        assertThatThrownBy(() -> chatService.start(me)).isInstanceOf(ForbiddenException.class);
    }

    @Test
    void startingAChatTwiceReusesTheExistingConversation() {
        actingAs(Role.ACADEMY_ADMIN);
        UUID student = UUID.randomUUID();
        AcademyMembership studentMembership = member(student, Role.STUDENT, MembershipStatus.ACTIVE, academyId);
        Conversation existing = conversationBetween(me, student);
        when(membershipRepository.findById(student)).thenReturn(Optional.of(studentMembership));
        when(conversationRepository.findByAcademyIdAndMemberLowIdAndMemberHighId(eq(academyId), any(), any()))
                .thenReturn(Optional.of(existing));
        when(membershipRepository.findAllById(Set.of(student))).thenReturn(List.of(studentMembership));
        when(userRepository.findAllById(any())).thenReturn(List.of(User.builder().id(studentMembership.getUserId()).fullName("Kavya").build()));

        var response = chatService.start(student);

        assertThat(response.id()).isEqualTo(existing.getId());
        verify(conversationRepository, never()).save(any());
    }

    @Test
    void aStrangersConversationIsNotFound() {
        actingAs(Role.STUDENT);
        Conversation theirs = conversationBetween(UUID.randomUUID(), UUID.randomUUID());
        when(conversationRepository.findById(theirs.getId())).thenReturn(Optional.of(theirs));

        assertThatThrownBy(() -> chatService.messages(theirs.getId())).isInstanceOf(ResourceNotFoundException.class);
        assertThatThrownBy(() -> chatService.send(theirs.getId(), "hi")).isInstanceOf(ResourceNotFoundException.class);
        assertThatThrownBy(() -> chatService.markRead(theirs.getId())).isInstanceOf(ResourceNotFoundException.class);
    }

    @Test
    void sendingBumpsTheOtherSidesUnreadAndNotMine() {
        actingAs(Role.ACADEMY_ADMIN);
        UUID student = UUID.randomUUID();
        Conversation conversation = conversationBetween(me, student);
        when(conversationRepository.findById(conversation.getId())).thenReturn(Optional.of(conversation));
        when(membershipRepository.findById(student)).thenReturn(Optional.of(member(student, Role.STUDENT, MembershipStatus.ACTIVE, academyId)));

        var sent = chatService.send(conversation.getId(), "  see you Saturday  ");

        assertThat(sent.body()).isEqualTo("see you Saturday");
        assertThat(sent.fromMe()).isTrue();
        boolean meIsLow = conversation.getMemberLowId().equals(me);
        verify(conversationRepository).recordMessage(eq(conversation.getId()), eq("see you Saturday"), eq(me), any(),
                eq(meIsLow ? 0 : 1), eq(meIsLow ? 1 : 0));
    }

    @Test
    void cannotSendToAnInactiveMember() {
        actingAs(Role.ACADEMY_ADMIN);
        UUID student = UUID.randomUUID();
        Conversation conversation = conversationBetween(me, student);
        when(conversationRepository.findById(conversation.getId())).thenReturn(Optional.of(conversation));
        when(membershipRepository.findById(student)).thenReturn(Optional.of(member(student, Role.STUDENT, MembershipStatus.REVOKED, academyId)));

        assertThatThrownBy(() -> chatService.send(conversation.getId(), "hi")).isInstanceOf(ForbiddenException.class);
        verify(messageRepository, never()).save(any());
        verify(conversationRepository, never()).recordMessage(any(), any(), any(), any(), anyInt(), anyInt());
    }

    @Test
    void messagesComeBackOldestFirstWithFromMeSet() {
        actingAs(Role.STUDENT);
        UUID admin = UUID.randomUUID();
        Conversation conversation = conversationBetween(me, admin);
        when(conversationRepository.findById(conversation.getId())).thenReturn(Optional.of(conversation));
        ChatMessage newer = ChatMessage.builder().id(UUID.randomUUID()).conversationId(conversation.getId()).senderMembershipId(admin).body("newer").build();
        ChatMessage older = ChatMessage.builder().id(UUID.randomUUID()).conversationId(conversation.getId()).senderMembershipId(me).body("older").build();
        when(messageRepository.findTop200ByConversationIdOrderByCreatedAtDesc(conversation.getId())).thenReturn(List.of(newer, older));

        var thread = chatService.messages(conversation.getId());

        assertThat(thread).extracting("body").containsExactly("older", "newer");
        assertThat(thread).extracting("fromMe").containsExactly(true, false);
    }

    @Test
    void markReadClearsOnlyMySide() {
        actingAs(Role.STUDENT);
        UUID admin = UUID.randomUUID();
        Conversation conversation = conversationBetween(me, admin);
        when(conversationRepository.findById(conversation.getId())).thenReturn(Optional.of(conversation));

        chatService.markRead(conversation.getId());

        if (conversation.getMemberLowId().equals(me)) {
            verify(conversationRepository).clearLowUnread(conversation.getId());
            verify(conversationRepository, never()).clearHighUnread(any());
        } else {
            verify(conversationRepository).clearHighUnread(conversation.getId());
            verify(conversationRepository, never()).clearLowUnread(any());
        }
    }

    @Test
    void orderedPairIsTheSameInEitherDirection() {
        UUID a = UUID.randomUUID();
        UUID b = UUID.randomUUID();
        assertThat(Conversation.orderedPair(a, b)).containsExactly(Conversation.orderedPair(b, a));
    }
}
