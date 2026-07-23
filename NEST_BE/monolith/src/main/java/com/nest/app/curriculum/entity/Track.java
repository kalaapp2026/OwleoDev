package com.nest.app.curriculum.entity;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.Id;
import jakarta.persistence.Index;
import jakarta.persistence.Table;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

import java.util.UUID;

/** PRD 3.11 / 4.5: a song attachment on a {@link SyllabusUnit}. {@code streamOnly} is the whole
 * "play from the app, or actually download" distinction - the frontend hides the download
 * affordance when true. Dev-stage caveat: {@code storageKey} is a plain static URL under
 * {@code /uploads/**} (same as every other upload in this app), not the short-lived signed URL a
 * real streaming setup would use - a determined user with the direct link could still download a
 * stream-only track outside the app. Enforcing that server-side is later infra work, not modelled
 * here. */
@Entity
@Table(name = "tracks", indexes = @Index(name = "idx_tracks_syllabus_unit", columnList = "syllabus_unit_id"))
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class Track {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(name = "syllabus_unit_id", nullable = false)
    private UUID syllabusUnitId;

    @Column(nullable = false)
    private String title;

    @Column(name = "storage_key", nullable = false)
    private String storageKey;

    @Column(name = "content_type")
    private String contentType;

    @Column(name = "stream_only", nullable = false)
    @Builder.Default
    private boolean streamOnly = true;
}
