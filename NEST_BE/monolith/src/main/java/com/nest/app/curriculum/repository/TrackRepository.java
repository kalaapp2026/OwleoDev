package com.nest.app.curriculum.repository;

import com.nest.app.curriculum.entity.Track;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.UUID;

public interface TrackRepository extends JpaRepository<Track, UUID> {
    List<Track> findBySyllabusUnitId(UUID syllabusUnitId);

    /** No FK cascade in this schema (consistent everywhere else) - SyllabusService deletes a
     * unit's tracks explicitly before deleting the unit itself. */
    void deleteBySyllabusUnitId(UUID syllabusUnitId);
}
