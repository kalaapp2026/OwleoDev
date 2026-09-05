package com.nest.app.curriculum.repository;

import com.nest.app.curriculum.entity.MaterialPlaylistEntry;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;
import java.util.UUID;

public interface MaterialPlaylistEntryRepository extends JpaRepository<MaterialPlaylistEntry, UUID> {

    List<MaterialPlaylistEntry> findByPlaylistIdOrderByPositionAsc(UUID playlistId);

    List<MaterialPlaylistEntry> findByPlaylistIdIn(List<UUID> playlistIds);

    /**
     * Clears a playlist before rewriting it, and empties it when the playlist is deleted.
     *
     * <p>flush + clear because a reorder deletes the old rows and inserts the new ones in the same
     * transaction: without them the inserts can reach the database before the deletes and collide,
     * and the persistence context would still hand back the stale rows afterwards.
     */
    @Modifying(flushAutomatically = true, clearAutomatically = true)
    @Query("delete from MaterialPlaylistEntry e where e.playlistId = :playlistId")
    void deleteByPlaylistId(@Param("playlistId") UUID playlistId);

    /**
     * Removes every appearance of a material, for when the material itself is deleted.
     *
     * <p>Without this a deleted file leaves entries pointing at nothing, and the playlist screen
     * either renders blanks or has to filter them out on every read.
     */
    @Modifying(flushAutomatically = true, clearAutomatically = true)
    @Query("delete from MaterialPlaylistEntry e where e.materialId = :materialId")
    void deleteByMaterialId(@Param("materialId") UUID materialId);
}
