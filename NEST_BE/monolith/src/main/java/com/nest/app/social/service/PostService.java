package com.nest.app.social.service;

import com.nest.app.academy.entity.Academy;
import com.nest.app.academy.repository.AcademyRepository;
import com.nest.app.identity.entity.AcademyMembership;
import com.nest.app.identity.entity.User;
import com.nest.app.identity.repository.AcademyMembershipRepository;
import com.nest.app.identity.repository.UserRepository;
import com.nest.app.social.dto.CreatePostRequest;
import com.nest.app.social.dto.PostResponse;
import com.nest.app.social.entity.Post;
import com.nest.app.social.entity.PostType;
import com.nest.app.social.entity.PostVisibility;
import com.nest.app.social.repository.PostRepository;
import com.nest.app.storage.FileStorageService;
import com.nest.common.audit.Auditable;
import com.nest.common.exception.ForbiddenException;
import com.nest.common.exception.ResourceNotFoundException;
import com.nest.common.security.FeatureKey;
import com.nest.common.security.MembershipClaim;
import com.nest.common.security.NestPrincipal;
import com.nest.common.security.Role;
import com.nest.common.security.TenantContext;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.multipart.MultipartFile;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;

/**
 * PRD 3.13 "Who can post": Super Admin and Academy Admin always can; a Trainer only with
 * ARTIST_STYLE_POSTING granted; Artist always (their own, membership-less identity); Student and
 * Guest never - both are consumption-only by design (PRD: "protects minors' content exposure").
 */
@Service
public class PostService {

    private static final Set<String> IMAGE_CONTENT_TYPES = Set.of("image/jpeg", "image/png", "image/webp");
    private static final long IMAGE_MAX_BYTES = 8L * 1024 * 1024;

    private final PostRepository postRepository;
    private final AcademyMembershipRepository membershipRepository;
    private final AcademyRepository academyRepository;
    private final UserRepository userRepository;
    private final FileStorageService fileStorageService;

    public PostService(PostRepository postRepository, AcademyMembershipRepository membershipRepository,
                        AcademyRepository academyRepository, UserRepository userRepository,
                        FileStorageService fileStorageService) {
        this.postRepository = postRepository;
        this.membershipRepository = membershipRepository;
        this.academyRepository = academyRepository;
        this.userRepository = userRepository;
        this.fileStorageService = fileStorageService;
    }

    @Transactional
    @Auditable(action = "POST_CREATED", entityType = "post")
    public PostResponse create(CreatePostRequest request) {
        NestPrincipal principal = TenantContext.require();
        AuthorIdentity author = resolveAuthorOrThrow(principal);

        Post post = Post.builder()
                .authorMembershipId(author.membershipId)
                .authorUserId(author.userId)
                .type(request.type())
                .content(request.content())
                .mediaUrls(request.mediaUrls() == null ? List.of() : request.mediaUrls())
                .visibility(request.visibility())
                .eventId(request.eventId())
                .build();
        // saveAndFlush, not save: @CreationTimestamp is populated when the INSERT actually runs,
        // which plain save() can defer past this point - reading createdAt back immediately would
        // otherwise see null.
        return toResponse(postRepository.saveAndFlush(post));
    }

    /** Called by event-service's flow when a Public event is published (PRD 3.12: "the same
     * event is also auto-published as a Social post from the Academy's verified profile"). */
    @Transactional
    @Auditable(action = "EVENT_POST_AUTO_CREATED", entityType = "post")
    public PostResponse createEventReferencePost(UUID authorMembershipId, UUID eventId, String title, String coverImageUrl) {
        Post post = Post.builder()
                .authorMembershipId(authorMembershipId)
                .type(PostType.EVENT_REF)
                .content(title)
                .mediaUrls(coverImageUrl == null ? List.of() : List.of(coverImageUrl))
                .visibility(PostVisibility.PUBLIC)
                .eventId(eventId)
                .build();
        // saveAndFlush, not save: @CreationTimestamp is populated when the INSERT actually runs,
        // which plain save() can defer past this point - reading createdAt back immediately would
        // otherwise see null.
        return toResponse(postRepository.saveAndFlush(post));
    }

    @Transactional(readOnly = true)
    public List<PostResponse> publicFeed() {
        return postRepository.findByVisibilityOrderByCreatedAtDesc(PostVisibility.PUBLIC).stream()
                .map(this::toResponse).collect(Collectors.toList());
    }

    /** One human's posts regardless of which "hat" they wore when posting: their own Artist/Super
     * Admin identity (authorUserId) PLUS every academy membership they hold that can post
     * (authorMembershipId, for Academy Admin/Trainer). Backs both "My Posts" and viewing someone
     * else's profile from Search - same query either way, just a different userId. */
    @Transactional(readOnly = true)
    public List<PostResponse> listByUser(UUID userId) {
        Set<UUID> membershipIds = membershipRepository.findByUserId(userId).stream()
                .map(AcademyMembership::getId).collect(Collectors.toSet());

        List<Post> posts = new ArrayList<>(postRepository.findByAuthorUserIdOrderByCreatedAtDesc(userId));
        if (!membershipIds.isEmpty()) {
            posts.addAll(postRepository.findByAuthorMembershipIdInOrderByCreatedAtDesc(membershipIds));
        }
        return posts.stream()
                .sorted(Comparator.comparing(Post::getCreatedAt).reversed())
                .map(this::toResponse)
                .collect(Collectors.toList());
    }

    /** Attaches one more image to an existing post (multiple calls = multiple images) - only the
     * post's own author may do this, checked by comparing THIS caller's resolved identity against
     * the post's stored author fields, not just "can this role post at all". */
    @Transactional
    @Auditable(action = "POST_MEDIA_ADDED", entityType = "post")
    public PostResponse attachMedia(UUID postId, MultipartFile file) {
        Post post = postRepository.findById(postId)
                .orElseThrow(() -> new ResourceNotFoundException("Post not found: " + postId));

        NestPrincipal principal = TenantContext.require();
        AuthorIdentity author = resolveAuthorOrThrow(principal);
        boolean isOwner = (author.userId != null && author.userId.equals(post.getAuthorUserId()))
                || (author.membershipId != null && author.membershipId.equals(post.getAuthorMembershipId()));
        if (!isOwner) {
            throw new ForbiddenException("You can only add media to your own post");
        }

        String url = fileStorageService.store(file, "post-media", IMAGE_CONTENT_TYPES, IMAGE_MAX_BYTES);
        List<String> updated = new ArrayList<>(post.getMediaUrls());
        updated.add(url);
        post.setMediaUrls(updated);
        return toResponse(postRepository.saveAndFlush(post));
    }

    /** Only the post's own author may delete it - Super Admin is the sole exception (moderation). */
    @Transactional
    @Auditable(action = "POST_DELETED", entityType = "post")
    public void delete(UUID postId) {
        Post post = postRepository.findById(postId)
                .orElseThrow(() -> new ResourceNotFoundException("Post not found: " + postId));

        NestPrincipal principal = TenantContext.require();
        if (!principal.isSuperAdmin()) {
            AuthorIdentity author = resolveAuthorOrThrow(principal);
            boolean isOwner = (author.userId != null && author.userId.equals(post.getAuthorUserId()))
                    || (author.membershipId != null && author.membershipId.equals(post.getAuthorMembershipId()));
            if (!isOwner) {
                throw new ForbiddenException("You can only delete your own post");
            }
        }
        postRepository.delete(post);
    }

    private AuthorIdentity resolveAuthorOrThrow(NestPrincipal principal) {
        if (principal.isSuperAdmin() || principal.globalRole() == Role.ARTIST) {
            return new AuthorIdentity(null, principal.userId());
        }

        MembershipClaim membership = principal.activeMembership()
                .orElseThrow(() -> new ForbiddenException("No active academy membership to post from"));

        if (membership.roleType() == Role.ACADEMY_ADMIN) {
            return new AuthorIdentity(membership.membershipId(), null);
        }
        if (membership.roleType() == Role.TRAINER && membership.hasFeature(FeatureKey.ARTIST_STYLE_POSTING)) {
            return new AuthorIdentity(membership.membershipId(), null);
        }
        throw new ForbiddenException("This role cannot post to the Social feed");
    }

    private PostResponse toResponse(Post p) {
        // new ArrayList<>(...) forces Hibernate to materialise this lazy @ElementCollection now,
        // while the session is still open - handing Jackson the live proxy instead blows up with
        // LazyInitializationException once serialization runs after the transaction has closed.
        String displayName;
        String avatarUrl;
        if (p.getAuthorMembershipId() != null) {
            // Posted via an academy membership (Admin, or a Trainer with ARTIST_STYLE_POSTING) -
            // always attributed to the ACADEMY, never the individual person who happened to post it.
            AcademyMembership membership = membershipRepository.findById(p.getAuthorMembershipId()).orElse(null);
            displayName = membership != null ? membership.getAcademyName() : "Academy";
            avatarUrl = membership != null
                    ? academyRepository.findById(membership.getAcademyId()).map(Academy::getLogoUrl).orElse(null)
                    : null;
        } else if (p.getAuthorUserId() != null) {
            // Posted via a personal, membership-less identity (Artist or Super Admin).
            User user = userRepository.findById(p.getAuthorUserId()).orElse(null);
            displayName = user != null ? user.getFullName() : "Unknown";
            avatarUrl = user != null ? user.getProfileImageUrl() : null;
        } else {
            displayName = "Unknown";
            avatarUrl = null;
        }

        return new PostResponse(p.getId(), p.getAuthorMembershipId(), p.getAuthorUserId(), p.getType(),
                p.getContent(), new java.util.ArrayList<>(p.getMediaUrls()), p.getVisibility(), p.getEventId(),
                p.getCreatedAt(), displayName, avatarUrl);
    }

    private record AuthorIdentity(UUID membershipId, UUID userId) {
    }
}
