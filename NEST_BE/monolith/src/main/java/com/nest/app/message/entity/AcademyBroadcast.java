package com.nest.app.message.entity;

import com.nest.app.event.entity.EventAudienceType;
import jakarta.persistence.CollectionTable;
import jakarta.persistence.Column;
import jakarta.persistence.ElementCollection;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.Id;
import jakarta.persistence.Index;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.Table;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;
import org.hibernate.annotations.CreationTimestamp;

import java.time.Instant;
import java.util.HashSet;
import java.util.Set;
import java.util.UUID;

/** One compose action of the Messages module (PRD-adjacent - built to match the reference
 * bundle's Messages tile): a broadcast an Academy Admin sent to a resolved audience, fanned out
 * as individual {@link com.nest.app.notification.entity.AppNotification} rows at send time.
 * {@code recipientCount} is captured once here rather than re-derived from the audience on every
 * read, since - unlike an Event's live "N invited" count - a sent broadcast's audience is a
 * historical fact, not something that should silently change as people join or leave courses
 * afterward. */
@Entity
@Table(name = "academy_broadcasts", indexes = @Index(name = "idx_academy_broadcasts_academy", columnList = "academy_id, created_at"))
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class AcademyBroadcast {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(name = "academy_id", nullable = false)
    private UUID academyId;

    @Column(nullable = false)
    private String title;

    @Column(columnDefinition = "text", nullable = false)
    private String body;

    @Enumerated(EnumType.STRING)
    @Column(name = "audience_type", nullable = false)
    private EventAudienceType audienceType;

    @ElementCollection
    @CollectionTable(name = "academy_broadcast_course_ids", joinColumns = @JoinColumn(name = "broadcast_id"))
    @Column(name = "course_id")
    @Builder.Default
    private Set<UUID> courseIds = new HashSet<>();

    @ElementCollection
    @CollectionTable(name = "academy_broadcast_batch_ids", joinColumns = @JoinColumn(name = "broadcast_id"))
    @Column(name = "batch_id")
    @Builder.Default
    private Set<UUID> batchIds = new HashSet<>();

    @ElementCollection
    @CollectionTable(name = "academy_broadcast_individual_ids", joinColumns = @JoinColumn(name = "broadcast_id"))
    @Column(name = "membership_id")
    @Builder.Default
    private Set<UUID> individualIds = new HashSet<>();

    @Column(name = "recipient_count", nullable = false)
    private int recipientCount;

    @Column(name = "created_by", nullable = false)
    private UUID createdBy;

    @CreationTimestamp
    @Column(name = "created_at", updatable = false)
    private Instant createdAt;
}
