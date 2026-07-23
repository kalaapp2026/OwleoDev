package com.nest.app.academy.entity;

import jakarta.persistence.CollectionTable;
import jakarta.persistence.Column;
import jakarta.persistence.ElementCollection;
import jakarta.persistence.Entity;
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

import java.util.HashSet;
import java.util.Set;
import java.util.UUID;

/** A "what we teach" marketing block on the About page - title + description + a photo carousel
 * (see {@link AcademyHighlightImage}) + the trainer(s)/Admin who teach it, hand-authored for
 * public display. Deliberately independent of the operational {@code courses} table (curriculum
 * module) so an inactive/internal course never needs to double as public-facing content. */
@Entity
@Table(name = "academy_highlights", indexes = @Index(name = "idx_academy_highlights_academy", columnList = "academy_id"))
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class AcademyHighlight {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(name = "academy_id", nullable = false)
    private UUID academyId;

    @Column(nullable = false)
    private String title;

    @Column(columnDefinition = "text")
    private String description;

    /** A Trainer's (or Academy Admin's - they can teach too) membership id, shown as an avatar
     * on the highlight card and in full on its detail view. */
    @ElementCollection
    @CollectionTable(name = "academy_highlight_trainers", joinColumns = @JoinColumn(name = "highlight_id"))
    @Column(name = "trainer_membership_id")
    @Builder.Default
    private Set<UUID> trainerMembershipIds = new HashSet<>();

    @Column(name = "order_index", nullable = false)
    @Builder.Default
    private int orderIndex = 0;
}
