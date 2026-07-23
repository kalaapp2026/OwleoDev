package com.nest.app.social.service;

import com.nest.app.social.dto.CreatePostRequest;
import com.nest.app.social.dto.PostResponse;
import com.nest.app.social.entity.Post;
import com.nest.app.social.entity.PostType;
import com.nest.app.social.entity.PostVisibility;
import com.nest.app.social.repository.PostRepository;
import com.nest.common.audit.Auditable;
import com.nest.common.exception.ForbiddenException;
import com.nest.common.security.FeatureKey;
import com.nest.common.security.MembershipClaim;
import com.nest.common.security.NestPrincipal;
import com.nest.common.security.Role;
import com.nest.common.security.TenantContext;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.UUID;
import java.util.stream.Collectors;

/**
 * PRD 3.13 "Who can post": Super Admin and Academy Admin always can; a Trainer only with
 * ARTIST_STYLE_POSTING granted; Artist always (their own, membership-less identity); Student and
 * Guest never - both are consumption-only by design (PRD: "protects minors' content exposure").
 */
@Service
public class PostService {

    private final PostRepository postRepository;

    public PostService(PostRepository postRepository) {
        this.postRepository = postRepository;
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
        return new PostResponse(p.getId(), p.getAuthorMembershipId(), p.getAuthorUserId(), p.getType(),
                p.getContent(), new java.util.ArrayList<>(p.getMediaUrls()), p.getVisibility(), p.getEventId(), p.getCreatedAt());
    }

    private record AuthorIdentity(UUID membershipId, UUID userId) {
    }
}
