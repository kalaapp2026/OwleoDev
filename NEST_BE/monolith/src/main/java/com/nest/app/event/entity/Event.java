package com.nest.app.event.entity;

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
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.HashSet;
import java.util.Set;
import java.util.UUID;

@Entity
@Table(name = "events", indexes = @Index(name = "idx_events_academy", columnList = "academy_id"))
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class Event {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(name = "academy_id", nullable = false)
    private UUID academyId;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private EventType type;

    @Column(nullable = false)
    private String title;

    @Column(columnDefinition = "text")
    private String description;

    @Column(name = "event_date", nullable = false)
    private LocalDateTime eventDate;

    private String location;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private EventVisibility visibility;

    @Column(name = "cover_image_url")
    private String coverImageUrl;

    /** For a multi-day event, the last day/time; for a same-day event with just an end time, the
     * same calendar day as eventDate with that end time. Null means no end was set at all. */
    @Column(name = "end_date")
    private LocalDateTime endDate;

    @Column(name = "venue_maps_url")
    private String venueMapsUrl;

    /** Interest can be marked until this day; null means open until the event itself. */
    @Column(name = "interest_deadline")
    private LocalDate interestDeadline;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    @Builder.Default
    private EventStatus status = EventStatus.PUBLISHED;

    @Enumerated(EnumType.STRING)
    @Column(name = "audience_type", nullable = false)
    @Builder.Default
    private EventAudienceType audienceType = EventAudienceType.ALL_STUDENTS;

    /** Whether the auto-publish-to-Social step has already fired - see EventService.maybePublishPost. */
    @Column(name = "post_published", nullable = false)
    @Builder.Default
    private boolean postPublished = false;

    @ElementCollection
    @CollectionTable(name = "event_course_ids", joinColumns = @JoinColumn(name = "event_id"))
    @Column(name = "course_id")
    @Builder.Default
    private Set<UUID> courseIds = new HashSet<>();

    @ElementCollection
    @CollectionTable(name = "event_batch_ids", joinColumns = @JoinColumn(name = "event_id"))
    @Column(name = "batch_id")
    @Builder.Default
    private Set<UUID> batchIds = new HashSet<>();

    @ElementCollection
    @CollectionTable(name = "event_individual_ids", joinColumns = @JoinColumn(name = "event_id"))
    @Column(name = "membership_id")
    @Builder.Default
    private Set<UUID> individualIds = new HashSet<>();

    @Column(name = "created_by", nullable = false)
    private UUID createdBy;

    @CreationTimestamp
    @Column(name = "created_at", updatable = false)
    private Instant createdAt;
}
