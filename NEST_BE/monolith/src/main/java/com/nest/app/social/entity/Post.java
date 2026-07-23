package com.nest.app.social.entity;

import jakarta.persistence.CollectionTable;
import jakarta.persistence.Column;
import jakarta.persistence.ElementCollection;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.Id;
import jakarta.persistence.Index;
import jakarta.persistence.Table;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;
import org.hibernate.annotations.CreationTimestamp;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

/**
 * PRD 3.13 / 4.4. {@code authorMembershipId} carries Academy Admin/Trainer posts;
 * {@code authorUserId} carries Artist/Super Admin posts, which aren't tied to any academy
 * membership. Exactly one of the two is set. {@code eventId} is populated only for
 * {@link PostType#EVENT_REF} posts auto-created when a Public event is published (PRD 3.12).
 */
@Entity
@Table(name = "posts", indexes = {
        @Index(name = "idx_posts_author_membership", columnList = "author_membership_id"),
        @Index(name = "idx_posts_visibility", columnList = "visibility")
})
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class Post {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(name = "author_membership_id")
    private UUID authorMembershipId;

    @Column(name = "author_user_id")
    private UUID authorUserId;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private PostType type;

    @Column(columnDefinition = "text")
    private String content;

    @ElementCollection
    @CollectionTable(name = "post_media_urls", joinColumns = @jakarta.persistence.JoinColumn(name = "post_id"))
    @Column(name = "media_url")
    @Builder.Default
    private List<String> mediaUrls = List.of();

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private PostVisibility visibility;

    @Column(name = "event_id")
    private UUID eventId;

    @CreationTimestamp
    @Column(name = "created_at", updatable = false)
    private Instant createdAt;
}
