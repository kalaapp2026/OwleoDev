package com.nest.app.message.entity;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;
import org.hibernate.annotations.CreationTimestamp;

import java.time.Instant;
import java.util.UUID;

/**
 * A one-to-one chat between two memberships of the same academy. The pair is stored low-id-first
 * (see {@link #of}) so there is exactly one row per pair however either side opens it. The last
 * message and each side's unread count live on the row so the chat list is one query.
 */
@Entity
@Table(name = "conversations")
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class Conversation {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(name = "academy_id", nullable = false)
    private UUID academyId;

    @Column(name = "member_low_id", nullable = false)
    private UUID memberLowId;

    @Column(name = "member_high_id", nullable = false)
    private UUID memberHighId;

    @Column(name = "low_unread", nullable = false)
    private int lowUnread;

    @Column(name = "high_unread", nullable = false)
    private int highUnread;

    @Column(name = "last_message_body", columnDefinition = "text")
    private String lastMessageBody;

    @Column(name = "last_sender_id")
    private UUID lastSenderId;

    @Column(name = "last_message_at", nullable = false)
    private Instant lastMessageAt;

    @CreationTimestamp
    @Column(name = "created_at", updatable = false)
    private Instant createdAt;

    /** Canonical ordering of a pair. Compares the string form because that matches how Postgres
     * orders uuids; {@link UUID#compareTo} compares signed longs and disagrees. */
    public static UUID[] orderedPair(UUID a, UUID b) {
        return a.toString().compareTo(b.toString()) <= 0 ? new UUID[] {a, b} : new UUID[] {b, a};
    }

    public boolean includes(UUID membershipId) {
        return memberLowId.equals(membershipId) || memberHighId.equals(membershipId);
    }

    public UUID otherThan(UUID membershipId) {
        return memberLowId.equals(membershipId) ? memberHighId : memberLowId;
    }

    public int unreadFor(UUID membershipId) {
        return memberLowId.equals(membershipId) ? lowUnread : highUnread;
    }
}
