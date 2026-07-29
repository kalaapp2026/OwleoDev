package com.nest.app.social.repository;

import com.nest.app.social.entity.Post;
import com.nest.app.social.entity.PostVisibility;
import org.springframework.data.jpa.repository.JpaRepository;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

public interface PostRepository extends JpaRepository<Post, UUID> {

    /** Super Admin platform metrics. */
    long countByCreatedAtAfter(Instant since);

    List<Post> findByVisibilityOrderByCreatedAtDesc(PostVisibility visibility);

    List<Post> findByAuthorMembershipIdOrderByCreatedAtDesc(UUID authorMembershipId);

    List<Post> findByAuthorUserIdOrderByCreatedAtDesc(UUID authorUserId);

    List<Post> findByAuthorMembershipIdInOrderByCreatedAtDesc(java.util.Collection<UUID> authorMembershipIds);
}
