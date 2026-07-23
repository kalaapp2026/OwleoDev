package com.nest.app.academy.entity;

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

/** One photo in a {@link AcademyHighlight}'s carousel - a highlight can carry several, unlike the
 * single-image model this replaced. Mirrors {@link com.nest.app.curriculum.entity.MaterialAttachment}'s shape. */
@Entity
@Table(name = "academy_highlight_images", indexes = @Index(name = "idx_academy_highlight_images_highlight", columnList = "highlight_id"))
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class AcademyHighlightImage {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(name = "highlight_id", nullable = false)
    private UUID highlightId;

    @Column(nullable = false)
    private String url;

    @Column(name = "order_index", nullable = false)
    @Builder.Default
    private int orderIndex = 0;
}
