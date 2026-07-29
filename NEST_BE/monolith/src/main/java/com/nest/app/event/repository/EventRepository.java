package com.nest.app.event.repository;

import com.nest.app.event.entity.Event;
import com.nest.app.event.entity.EventVisibility;
import org.springframework.data.jpa.repository.JpaRepository;

import java.time.LocalDateTime;
import java.util.List;
import java.util.UUID;

public interface EventRepository extends JpaRepository<Event, UUID> {
    List<Event> findByAcademyId(UUID academyId);

    List<Event> findByVisibility(EventVisibility visibility);

    // ---- Super Admin platform metrics ----

    /** Still-upcoming events across every academy. */
    long countByEventDateAfter(LocalDateTime now);

    long countByAcademyId(UUID academyId);
}
