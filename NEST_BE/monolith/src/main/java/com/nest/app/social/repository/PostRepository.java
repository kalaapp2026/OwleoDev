package com.nest.app.social.repository;

import com.nest.app.social.entity.Post;
import com.nest.app.social.entity.PostVisibility;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.UUID;

public interface PostRepository extends JpaRepository<Post, UUID> {
    List<Post> findByVisibilityOrderByCreatedAtDesc(PostVisibility visibility);

    List<Post> findByAuthorMembershipIdOrderByCreatedAtDesc(UUID authorMembershipId);
}
