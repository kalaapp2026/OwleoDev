package com.nest.app.message.repository;

import com.nest.app.message.entity.Conversation;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

public interface ConversationRepository extends JpaRepository<Conversation, UUID> {

    Optional<Conversation> findByAcademyIdAndMemberLowIdAndMemberHighId(UUID academyId, UUID lowId, UUID highId);

    @Query("select c from Conversation c where c.academyId = :academyId "
            + "and (c.memberLowId = :membershipId or c.memberHighId = :membershipId) "
            + "order by c.lastMessageAt desc")
    List<Conversation> findForMember(@Param("academyId") UUID academyId, @Param("membershipId") UUID membershipId);

    // Counter bumps are single UPDATEs so two people sending at once cannot lose an increment the
    // way load-modify-save would.
    @Modifying
    @Query("update Conversation c set c.lastMessageBody = :body, c.lastSenderId = :senderId, c.lastMessageAt = :at, "
            + "c.lowUnread = c.lowUnread + :lowDelta, c.highUnread = c.highUnread + :highDelta where c.id = :id")
    void recordMessage(@Param("id") UUID id, @Param("body") String body, @Param("senderId") UUID senderId,
                       @Param("at") Instant at, @Param("lowDelta") int lowDelta, @Param("highDelta") int highDelta);

    @Modifying
    @Query("update Conversation c set c.lowUnread = 0 where c.id = :id")
    void clearLowUnread(@Param("id") UUID id);

    @Modifying
    @Query("update Conversation c set c.highUnread = 0 where c.id = :id")
    void clearHighUnread(@Param("id") UUID id);
}
