package com.nest.app.social.repository;

import com.nest.app.social.entity.Post;
import com.nest.app.social.entity.PostVisibility;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

public interface PostRepository extends JpaRepository<Post, UUID> {

    /** Super Admin platform metrics. */
    long countByCreatedAtAfter(Instant since);

    /** Posts per academy, for every academy at once. Only counts posts made AS an academy
     * (authorMembershipId); an Artist's personal post belongs to no academy. */
    @Query("""
            select m.academyId, count(p)
            from Post p, AcademyMembership m
            where p.authorMembershipId = m.id
            group by m.academyId
            """)
    List<Object[]> countByAcademyGrouped();

    List<Post> findByVisibilityOrderByCreatedAtDesc(PostVisibility visibility);

    List<Post> findByAuthorMembershipIdOrderByCreatedAtDesc(UUID authorMembershipId);

    List<Post> findByAuthorUserIdOrderByCreatedAtDesc(UUID authorUserId);

    List<Post> findByAuthorMembershipIdInOrderByCreatedAtDesc(java.util.Collection<UUID> authorMembershipIds);
}
