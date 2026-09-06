package com.nest.app.curriculum.service;

import com.nest.app.curriculum.dto.PlaylistResponse;
import com.nest.app.curriculum.dto.StudyMaterialResponse;
import com.nest.app.curriculum.entity.MaterialPlaylist;
import com.nest.app.curriculum.entity.MaterialPlaylistEntry;
import com.nest.app.curriculum.repository.MaterialPlaylistEntryRepository;
import com.nest.app.curriculum.repository.MaterialPlaylistRepository;
import com.nest.common.audit.Auditable;
import com.nest.common.exception.BadRequestException;
import com.nest.common.exception.ForbiddenException;
import com.nest.common.exception.ResourceNotFoundException;
import com.nest.common.security.TenantContext;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.stream.Collectors;

/**
 * A trainer's own running orders over the audio they have uploaded.
 *
 * <p>Private to the membership that created them. There is no sharing model and deliberately no
 * academy-wide list: a playlist is a personal teaching aid, closer to a bookmark than to content,
 * and surfacing one trainer's to another would invite editing each other's lesson plans.
 */
@Service
public class MaterialPlaylistService {

    private final MaterialPlaylistRepository playlistRepository;
    private final MaterialPlaylistEntryRepository entryRepository;
    private final StudyMaterialService studyMaterialService;

    public MaterialPlaylistService(MaterialPlaylistRepository playlistRepository,
                                    MaterialPlaylistEntryRepository entryRepository,
                                    StudyMaterialService studyMaterialService) {
        this.playlistRepository = playlistRepository;
        this.entryRepository = entryRepository;
        this.studyMaterialService = studyMaterialService;
    }

    @Transactional(readOnly = true)
    public List<PlaylistResponse> list() {
        List<MaterialPlaylist> playlists =
                playlistRepository.findByMembershipIdOrderByCreatedAtAsc(currentMembershipId());
        if (playlists.isEmpty()) {
            return List.of();
        }

        // Entries for every playlist in one query, then the materials for all of them in one more.
        // Done per playlist this would be two queries per row on a screen that lists them all.
        Map<UUID, List<MaterialPlaylistEntry>> entriesByPlaylist = entryRepository
                .findByPlaylistIdIn(playlists.stream().map(MaterialPlaylist::getId).toList())
                .stream()
                .collect(Collectors.groupingBy(MaterialPlaylistEntry::getPlaylistId));

        Map<UUID, StudyMaterialResponse> materials = resolveMaterials(
                entriesByPlaylist.values().stream().flatMap(List::stream).toList());

        return playlists.stream()
                .map(p -> toResponse(p, entriesByPlaylist.getOrDefault(p.getId(), List.of()), materials))
                .collect(Collectors.toList());
    }

    @Transactional(readOnly = true)
    public PlaylistResponse get(UUID playlistId) {
        MaterialPlaylist playlist = mine(playlistId);
        List<MaterialPlaylistEntry> entries = entryRepository.findByPlaylistIdOrderByPositionAsc(playlistId);
        return toResponse(playlist, entries, resolveMaterials(entries));
    }

    @Transactional
    @Auditable(action = "PLAYLIST_CREATED", entityType = "material_playlist")
    public PlaylistResponse create(String name) {
        if (name == null || name.isBlank()) {
            throw new BadRequestException("Give this playlist a name");
        }
        MaterialPlaylist playlist = playlistRepository.save(MaterialPlaylist.builder()
                .membershipId(currentMembershipId())
                .academyId(TenantContext.currentAcademyId())
                .name(name.trim())
                .build());
        return toResponse(playlist, List.of(), Map.of());
    }

    @Transactional
    public PlaylistResponse rename(UUID playlistId, String name) {
        if (name == null || name.isBlank()) {
            throw new BadRequestException("Give this playlist a name");
        }
        MaterialPlaylist playlist = mine(playlistId);
        playlist.setName(name.trim());
        playlistRepository.save(playlist);
        return get(playlistId);
    }

    @Transactional
    @Auditable(action = "PLAYLIST_DELETED", entityType = "material_playlist")
    public void delete(UUID playlistId) {
        MaterialPlaylist playlist = mine(playlistId);
        entryRepository.deleteByPlaylistId(playlistId);
        playlistRepository.delete(playlist);
    }

    /**
     * Appends materials to the end, in the order given.
     *
     * <p>Adding a piece already present is allowed rather than ignored - repeating one is the
     * point of entries having their own ids.
     */
    @Transactional
    public PlaylistResponse addMaterials(UUID playlistId, List<UUID> materialIds) {
        mine(playlistId);
        if (materialIds == null || materialIds.isEmpty()) {
            return get(playlistId);
        }
        int next = entryRepository.findByPlaylistIdOrderByPositionAsc(playlistId).size();
        for (UUID materialId : materialIds) {
            // Routed through the material service so a playlist cannot reference a file the caller
            // has no business seeing.
            studyMaterialService.assertReadable(materialId);
            entryRepository.save(MaterialPlaylistEntry.builder()
                    .playlistId(playlistId)
                    .materialId(materialId)
                    .position(next++)
                    .build());
        }
        return get(playlistId);
    }

    @Transactional
    public PlaylistResponse removeEntry(UUID playlistId, UUID entryId) {
        mine(playlistId);
        MaterialPlaylistEntry entry = entryRepository.findById(entryId)
                .orElseThrow(() -> new ResourceNotFoundException("Entry not found: " + entryId));
        if (!entry.getPlaylistId().equals(playlistId)) {
            throw new ForbiddenException("That entry belongs to a different playlist");
        }
        entryRepository.delete(entry);
        renumber(playlistId);
        return get(playlistId);
    }

    /** Duplicating an entry is how the same piece gets a second pass at a different tempo. */
    @Transactional
    public PlaylistResponse duplicateEntry(UUID playlistId, UUID entryId) {
        mine(playlistId);
        MaterialPlaylistEntry entry = entryRepository.findById(entryId)
                .orElseThrow(() -> new ResourceNotFoundException("Entry not found: " + entryId));
        if (!entry.getPlaylistId().equals(playlistId)) {
            throw new ForbiddenException("That entry belongs to a different playlist");
        }
        List<MaterialPlaylistEntry> entries = entryRepository.findByPlaylistIdOrderByPositionAsc(playlistId);
        int insertAt = entry.getPosition() + 1;
        // Shift everything after it down, so the copy lands immediately below its original rather
        // than at the end where it reads as unrelated.
        entries.stream().filter(e -> e.getPosition() >= insertAt).forEach(e -> {
            e.setPosition(e.getPosition() + 1);
            entryRepository.save(e);
        });
        entryRepository.save(MaterialPlaylistEntry.builder()
                .playlistId(playlistId)
                .materialId(entry.getMaterialId())
                .position(insertAt)
                .build());
        return get(playlistId);
    }

    /**
     * Rewrites the running order from a full list of entry ids.
     *
     * <p>Takes the whole order rather than a from/to pair: a drag can move a row several places,
     * and reconciling one move against a list the client has already re-rendered is how orders
     * drift apart. Any entry the client omits keeps its place at the end.
     */
    @Transactional
    public PlaylistResponse reorder(UUID playlistId, List<UUID> entryIds) {
        mine(playlistId);
        List<MaterialPlaylistEntry> entries = entryRepository.findByPlaylistIdOrderByPositionAsc(playlistId);
        Map<UUID, MaterialPlaylistEntry> byId = entries.stream()
                .collect(Collectors.toMap(MaterialPlaylistEntry::getId, e -> e));

        int position = 0;
        List<MaterialPlaylistEntry> ordered = new ArrayList<>();
        if (entryIds != null) {
            for (UUID id : entryIds) {
                MaterialPlaylistEntry entry = byId.remove(id);
                if (entry == null) {
                    // Silently skipped rather than rejected: an id the client thinks exists but the
                    // server has already removed is a stale view, not a reason to lose the reorder.
                    continue;
                }
                entry.setPosition(position++);
                ordered.add(entry);
            }
        }
        for (MaterialPlaylistEntry leftover : byId.values()) {
            leftover.setPosition(position++);
            ordered.add(leftover);
        }
        entryRepository.saveAll(ordered);
        return get(playlistId);
    }

    // -----------------------------------------------------------------------

    private void renumber(UUID playlistId) {
        List<MaterialPlaylistEntry> entries = entryRepository.findByPlaylistIdOrderByPositionAsc(playlistId);
        for (int i = 0; i < entries.size(); i++) {
            entries.get(i).setPosition(i);
        }
        entryRepository.saveAll(entries);
    }

    private MaterialPlaylist mine(UUID playlistId) {
        MaterialPlaylist playlist = playlistRepository.findById(playlistId)
                .orElseThrow(() -> new ResourceNotFoundException("Playlist not found: " + playlistId));
        if (!playlist.getMembershipId().equals(currentMembershipId())) {
            // Deliberately the same message whether it belongs to someone else or to another
            // academy - neither is any of this caller's business.
            throw new ForbiddenException("That playlist isn't yours");
        }
        return playlist;
    }

    private UUID currentMembershipId() {
        return TenantContext.require().activeMembership()
                .orElseThrow(() -> new ForbiddenException("Request has no active academy membership"))
                .membershipId();
    }

    /** Resolves every entry's material in one call, keyed by material id. */
    private Map<UUID, StudyMaterialResponse> resolveMaterials(List<MaterialPlaylistEntry> entries) {
        if (entries.isEmpty()) {
            return Map.of();
        }
        return studyMaterialService.byIds(entries.stream()
                        .map(MaterialPlaylistEntry::getMaterialId)
                        .distinct()
                        .toList()).stream()
                .collect(Collectors.toMap(StudyMaterialResponse::id, m -> m));
    }

    private PlaylistResponse toResponse(MaterialPlaylist playlist,
                                         List<MaterialPlaylistEntry> entries,
                                         Map<UUID, StudyMaterialResponse> materials) {
        Map<UUID, PlaylistResponse.PlaylistEntryResponse> ordered = new LinkedHashMap<>();
        entries.stream()
                .sorted(Comparator.comparingInt(MaterialPlaylistEntry::getPosition))
                .forEach(e -> {
                    StudyMaterialResponse material = materials.get(e.getMaterialId());
                    // A material deleted out from under the playlist is skipped rather than
                    // rendered as a blank row. deleteByMaterialId should have removed the entry,
                    // so this is the belt to that braces.
                    if (material != null) {
                        ordered.put(e.getId(), new PlaylistResponse.PlaylistEntryResponse(
                                e.getId(), e.getPosition(), material));
                    }
                });
        return new PlaylistResponse(playlist.getId(), playlist.getName(), playlist.getCreatedAt(),
                List.copyOf(ordered.values()));
    }
}
