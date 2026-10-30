package com.nest.app.enrolment.service;

import com.nest.app.enrolment.entity.Batch;
import com.nest.app.identity.entity.CourseMap;
import com.nest.app.identity.repository.CourseMapRepository;
import org.springframework.stereotype.Component;

import java.util.Collection;
import java.util.HashMap;
import java.util.LinkedHashSet;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

/**
 * Which of a batch's courses a student holds. A batch can span Basic, Intermediate and Advanced, and a
 * student belongs to the ones they are enrolled in; that decides which trainers may see and mark them,
 * which "one Regular batch per course" rule applies, and which course name tags their row.
 *
 * <p>A student with no active enrolment in ANY of the batch's courses (a legacy roster, or a data slip)
 * is treated as holding all of them, so every rule fails safe - they are checked against, and seen
 * by, everyone who has the batch - rather than slipping through unchecked or vanishing.
 */
@Component
public class StudentBatchCourses {

    private final CourseMapRepository courseMapRepository;

    public StudentBatchCourses(CourseMapRepository courseMapRepository) {
        this.courseMapRepository = courseMapRepository;
    }

    /** Active course enrolments per membership, one query for the lot. */
    public Map<UUID, Set<UUID>> activeEnrolments(Collection<UUID> membershipIds) {
        Map<UUID, Set<UUID>> byMembership = new HashMap<>();
        if (membershipIds.isEmpty()) {
            return byMembership;
        }
        for (CourseMap cm : courseMapRepository.findByMembershipIdIn(membershipIds)) {
            if (cm.isActive()) {
                byMembership.computeIfAbsent(cm.getMembershipId(), k -> new LinkedHashSet<>()).add(cm.getCourseId());
            }
        }
        return byMembership;
    }

    /** The batch's courses this student holds, in the batch's course order. */
    public Set<UUID> inBatch(Batch batch, UUID membershipId) {
        return inBatch(batch, membershipId, activeEnrolments(java.util.List.of(membershipId)));
    }

    /** Same, using enrolments already loaded for a whole roster. */
    public Set<UUID> inBatch(Batch batch, UUID membershipId, Map<UUID, Set<UUID>> enrolled) {
        Set<UUID> inBatch = batch.allCourseIds();
        Set<UUID> theirs = new LinkedHashSet<>();
        Set<UUID> mine = enrolled.getOrDefault(membershipId, Set.of());
        for (UUID courseId : inBatch) {
            if (mine.contains(courseId)) {
                theirs.add(courseId);
            }
        }
        return theirs.isEmpty() ? inBatch : theirs;
    }
}
