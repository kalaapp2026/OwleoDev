package com.nest.app.academy.repository;

import com.nest.app.academy.entity.AcademyHighlightImage;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.UUID;

public interface AcademyHighlightImageRepository extends JpaRepository<AcademyHighlightImage, UUID> {
    List<AcademyHighlightImage> findByHighlightIdOrderByOrderIndex(UUID highlightId);

    void deleteByHighlightId(UUID highlightId);
}
