package com.nest.app.attendance.repository;

import com.nest.app.attendance.entity.Attendance;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

public interface AttendanceRepository extends JpaRepository<Attendance, UUID> {
    List<Attendance> findByClassInstanceId(UUID classInstanceId);

    Optional<Attendance> findByClassInstanceIdAndMembershipId(UUID classInstanceId, UUID membershipId);

    List<Attendance> findByMembershipIdOrderByMarkedAtDesc(UUID membershipId);

    List<Attendance> findByMembershipIdAndClassInstanceIdIn(UUID membershipId, List<UUID> classInstanceIds);
}
