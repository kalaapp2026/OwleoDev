package com.nest.app.social.service;

import com.nest.app.academy.repository.AcademyRepository;
import com.nest.app.identity.repository.AcademyMembershipRepository;
import com.nest.app.identity.repository.UserRepository;
import com.nest.app.social.dto.CreatePostRequest;
import com.nest.app.social.entity.Post;
import com.nest.app.social.entity.PostType;
import com.nest.app.social.entity.PostVisibility;
import com.nest.app.social.repository.PostRepository;
import com.nest.app.storage.FileStorageService;
import com.nest.common.exception.ForbiddenException;
import com.nest.common.security.FeatureKey;
import com.nest.common.security.MembershipClaim;
import com.nest.common.security.NestPrincipal;
import com.nest.common.security.Role;
import com.nest.common.security.TenantContext;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.List;
import java.util.Set;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/** Covers PRD 3.13 "who can post": Admin/Artist/SuperAdmin always; Trainer only with
 * ARTIST_STYLE_POSTING; Student/Guest never. */
@ExtendWith(MockitoExtension.class)
class PostServiceTest {

    @Mock
    private PostRepository postRepository;
    @Mock
    private AcademyMembershipRepository membershipRepository;
    @Mock
    private AcademyRepository academyRepository;
    @Mock
    private UserRepository userRepository;
    @Mock
    private FileStorageService fileStorageService;

    private PostService postService;

    private static final CreatePostRequest REQUEST = new CreatePostRequest(PostType.NORMAL, "hello", List.of(), PostVisibility.PUBLIC, null);

    @AfterEach
    void tearDown() {
        TenantContext.clear();
    }

    private void mockSaveReturnsInput() {
        when(postRepository.saveAndFlush(any(Post.class))).thenAnswer(inv -> {
            Post p = inv.getArgument(0);
            p.setId(UUID.randomUUID());
            return p;
        });
    }

    @Test
    void studentCannotPost() {
        postService = new PostService(postRepository, membershipRepository, academyRepository, userRepository, fileStorageService);
        UUID membershipId = UUID.randomUUID();
        MembershipClaim claim = new MembershipClaim(membershipId, UUID.randomUUID(), "Natyalaya", Role.STUDENT, Set.of(), Set.of());
        TenantContext.set(new NestPrincipal(UUID.randomUUID(), "priya", Role.STUDENT, List.of(claim), membershipId));

        assertThatThrownBy(() -> postService.create(REQUEST)).isInstanceOf(ForbiddenException.class);
    }

    @Test
    void trainerWithoutArtistStylePostingCannotPost() {
        postService = new PostService(postRepository, membershipRepository, academyRepository, userRepository, fileStorageService);
        UUID membershipId = UUID.randomUUID();
        MembershipClaim claim = new MembershipClaim(membershipId, UUID.randomUUID(), "Natyalaya", Role.TRAINER, Set.of(FeatureKey.ATTENDANCE), Set.of());
        TenantContext.set(new NestPrincipal(UUID.randomUUID(), "ravi", Role.TRAINER, List.of(claim), membershipId));

        assertThatThrownBy(() -> postService.create(REQUEST)).isInstanceOf(ForbiddenException.class);
    }

    @Test
    void trainerWithArtistStylePostingCanPost() {
        postService = new PostService(postRepository, membershipRepository, academyRepository, userRepository, fileStorageService);
        mockSaveReturnsInput();
        UUID membershipId = UUID.randomUUID();
        MembershipClaim claim = new MembershipClaim(membershipId, UUID.randomUUID(), "Natyalaya", Role.TRAINER,
                Set.of(FeatureKey.ARTIST_STYLE_POSTING), Set.of());
        TenantContext.set(new NestPrincipal(UUID.randomUUID(), "ravi", Role.TRAINER, List.of(claim), membershipId));

        var response = postService.create(REQUEST);
        assertThat(response.authorMembershipId()).isEqualTo(membershipId);
    }

    @Test
    void academyAdminCanAlwaysPost() {
        postService = new PostService(postRepository, membershipRepository, academyRepository, userRepository, fileStorageService);
        mockSaveReturnsInput();
        UUID membershipId = UUID.randomUUID();
        MembershipClaim claim = new MembershipClaim(membershipId, UUID.randomUUID(), "Natyalaya", Role.ACADEMY_ADMIN, Set.of(), Set.of());
        TenantContext.set(new NestPrincipal(UUID.randomUUID(), "meera", Role.ACADEMY_ADMIN, List.of(claim), membershipId));

        assertThatCode(() -> postService.create(REQUEST)).doesNotThrowAnyException();
    }

    @Test
    void artistCanPostWithNoAcademyMembershipAtAll() {
        postService = new PostService(postRepository, membershipRepository, academyRepository, userRepository, fileStorageService);
        mockSaveReturnsInput();
        UUID artistUserId = UUID.randomUUID();
        TenantContext.set(new NestPrincipal(artistUserId, "artist_x", Role.ARTIST, List.of(), null));

        var response = postService.create(REQUEST);
        assertThat(response.authorUserId()).isEqualTo(artistUserId);
        assertThat(response.authorMembershipId()).isNull();
    }

    @Test
    void guestCannotPost() {
        postService = new PostService(postRepository, membershipRepository, academyRepository, userRepository, fileStorageService);
        TenantContext.set(new NestPrincipal(UUID.randomUUID(), "guest_x", Role.GUEST, List.of(), null));

        assertThatThrownBy(() -> postService.create(REQUEST)).isInstanceOf(ForbiddenException.class);
    }

    @Test
    void deleteRejectsSomeoneWhoIsNotThePostsAuthor() {
        postService = new PostService(postRepository, membershipRepository, academyRepository, userRepository, fileStorageService);
        UUID postId = UUID.randomUUID();
        Post post = Post.builder().id(postId).authorUserId(UUID.randomUUID()).mediaUrls(List.of()).build();
        when(postRepository.findById(postId)).thenReturn(java.util.Optional.of(post));
        TenantContext.set(new NestPrincipal(UUID.randomUUID(), "impostor", Role.ARTIST, List.of(), null));

        assertThatThrownBy(() -> postService.delete(postId)).isInstanceOf(ForbiddenException.class);
    }

    @Test
    void deleteAllowsTheAuthorAndSuperAdminAlways() {
        postService = new PostService(postRepository, membershipRepository, academyRepository, userRepository, fileStorageService);
        UUID postId = UUID.randomUUID();
        UUID authorUserId = UUID.randomUUID();
        Post post = Post.builder().id(postId).authorUserId(authorUserId).mediaUrls(List.of()).build();
        when(postRepository.findById(postId)).thenReturn(java.util.Optional.of(post));

        // Super Admin, not the author, can still moderate-delete.
        TenantContext.set(new NestPrincipal(UUID.randomUUID(), "root", Role.SUPER_ADMIN, List.of(), null));
        assertThatCode(() -> postService.delete(postId)).doesNotThrowAnyException();
        verify(postRepository).delete(post);
    }

    @Test
    void attachMediaRejectsSomeoneWhoIsNotThePostsAuthor() {
        postService = new PostService(postRepository, membershipRepository, academyRepository, userRepository, fileStorageService);
        UUID postId = UUID.randomUUID();
        UUID realAuthorUserId = UUID.randomUUID();
        Post post = Post.builder().id(postId).authorUserId(realAuthorUserId).mediaUrls(List.of()).build();
        when(postRepository.findById(postId)).thenReturn(java.util.Optional.of(post));

        // A different Artist tries to add media to someone else's post.
        TenantContext.set(new NestPrincipal(UUID.randomUUID(), "impostor", Role.ARTIST, List.of(), null));

        assertThatThrownBy(() -> postService.attachMedia(postId, null)).isInstanceOf(ForbiddenException.class);
    }

    @Test
    void listByUserMergesArtistIdentityAndAcademyMembershipPosts() {
        postService = new PostService(postRepository, membershipRepository, academyRepository, userRepository, fileStorageService);
        UUID userId = UUID.randomUUID();
        UUID membershipId = UUID.randomUUID();

        when(membershipRepository.findByUserId(userId)).thenReturn(List.of(
                com.nest.app.identity.entity.AcademyMembership.builder().id(membershipId).build()));

        Post ownPost = Post.builder().id(UUID.randomUUID()).authorUserId(userId)
                .createdAt(java.time.Instant.now()).mediaUrls(List.of()).build();
        Post academyPost = Post.builder().id(UUID.randomUUID()).authorMembershipId(membershipId)
                .createdAt(java.time.Instant.now().minusSeconds(60)).mediaUrls(List.of()).build();
        when(postRepository.findByAuthorUserIdOrderByCreatedAtDesc(userId)).thenReturn(List.of(ownPost));
        when(postRepository.findByAuthorMembershipIdInOrderByCreatedAtDesc(Set.of(membershipId))).thenReturn(List.of(academyPost));

        var result = postService.listByUser(userId);

        assertThat(result).hasSize(2);
        assertThat(result.get(0).id()).isEqualTo(ownPost.getId()); // newer first
    }
}
