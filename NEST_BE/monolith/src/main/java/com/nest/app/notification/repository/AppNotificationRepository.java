package com.nest.app.notification.repository;

import com.nest.app.notification.entity.AppNotification;
import com.nest.app.notification.entity.NotificationModule;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.Instant;
import java.util.Collection;
import java.util.List;
import java.util.UUID;

public interface AppNotificationRepository extends JpaRepository<AppNotification, UUID> {
    List<AppNotification> findByUserIdAndModuleOrderByCreatedAtDesc(UUID userId, NotificationModule module);

    long countByUserIdAndModuleAndReadAtIsNull(UUID userId, NotificationModule module);

    /** Every recipient's copy of one broadcast - the sender's per-person read list. */
    List<AppNotification> findByBroadcastId(UUID broadcastId);

    /** The retention sweep: everything older than {@code cutoff}. Returns how many rows went. */
    @Modifying(flushAutomatically = true, clearAutomatically = true)
    @Query("delete from AppNotification n where n.createdAt < :cutoff")
    int deleteCreatedBefore(@Param("cutoff") Instant cutoff);

    /** {broadcastId, copies delivered, copies read} per broadcast - one query for a whole list. */
    @Query("select n.broadcastId, count(n), count(n.readAt) from AppNotification n "
            + "where n.broadcastId in :ids group by n.broadcastId")
    List<Object[]> readStatsForBroadcasts(@Param("ids") Collection<UUID> ids);
}
