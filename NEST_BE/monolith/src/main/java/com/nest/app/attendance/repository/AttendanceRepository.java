package com.nest.app.attendance.repository;

import com.nest.app.attendance.entity.Attendance;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

public interface AttendanceRepository extends JpaRepository<Attendance, UUID> {
    List<Attendance> findByClassInstanceId(UUID classInstanceId);

    /** Which classes in a window have been marked at all - the schedule/attendance feed's
     * "Marked / Not marked" chip, resolved in one query rather than one per class. */
    List<Attendance> findByClassInstanceIdIn(Collection<UUID> classInstanceIds);

    Optional<Attendance> findByClassInstanceIdAndMembershipId(UUID classInstanceId, UUID membershipId);

    List<Attendance> findByMembershipIdOrderByMarkedAtDesc(UUID membershipId);

    List<Attendance> findByMembershipIdAndClassInstanceIdIn(UUID membershipId, List<UUID> classInstanceIds);
}
