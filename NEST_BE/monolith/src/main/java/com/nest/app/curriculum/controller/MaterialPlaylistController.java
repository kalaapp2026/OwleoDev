package com.nest.app.curriculum.controller;

import com.nest.app.curriculum.dto.PlaybackSettingsRequest;
import com.nest.app.curriculum.dto.PlaybackSettingsResponse;
import com.nest.app.curriculum.dto.PlaylistResponse;
import com.nest.app.curriculum.service.MaterialPlaybackService;
import com.nest.app.curriculum.service.MaterialPlaylistService;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.Map;
import java.util.UUID;

/**
 * Playlists and per-person playback settings.
 *
 * <p>None of it carries {@code @RequiresFeature}. A playlist is a personal aid over material the
 * caller can already see, and playback settings belong to whoever is listening - a student
 * slowing a backing track down to practise holds no course grant at all. Both services scope by
 * the caller's own membership instead.
 */
@RestController
@Tag(name = "Study Material")
public class MaterialPlaylistController {

    private final MaterialPlaylistService playlistService;
    private final MaterialPlaybackService playbackService;

    public MaterialPlaylistController(MaterialPlaylistService playlistService,
                                       MaterialPlaybackService playbackService) {
        this.playlistService = playlistService;
        this.playbackService = playbackService;
    }

    @GetMapping("/material-playlists")
    public List<PlaylistResponse> list() {
        return playlistService.list();
    }

    @GetMapping("/material-playlists/{id}")
    public PlaylistResponse get(@PathVariable UUID id) {
        return playlistService.get(id);
    }

    @PostMapping("/material-playlists")
    public PlaylistResponse create(@RequestBody Map<String, String> body) {
        return playlistService.create(body.get("name"));
    }

    @PutMapping("/material-playlists/{id}")
    public PlaylistResponse rename(@PathVariable UUID id, @RequestBody Map<String, String> body) {
        return playlistService.rename(id, body.get("name"));
    }

    @DeleteMapping("/material-playlists/{id}")
    public void delete(@PathVariable UUID id) {
        playlistService.delete(id);
    }

    @PostMapping("/material-playlists/{id}/entries")
    public PlaylistResponse addMaterials(@PathVariable UUID id,
                                          @RequestBody Map<String, List<UUID>> body) {
        return playlistService.addMaterials(id, body.get("materialIds"));
    }

    @DeleteMapping("/material-playlists/{id}/entries/{entryId}")
    public PlaylistResponse removeEntry(@PathVariable UUID id, @PathVariable UUID entryId) {
        return playlistService.removeEntry(id, entryId);
    }

    @PostMapping("/material-playlists/{id}/entries/{entryId}/duplicate")
    public PlaylistResponse duplicateEntry(@PathVariable UUID id, @PathVariable UUID entryId) {
        return playlistService.duplicateEntry(id, entryId);
    }

    /** Takes the whole running order, not a from/to pair - see the service for why. */
    @PutMapping("/material-playlists/{id}/order")
    public PlaylistResponse reorder(@PathVariable UUID id,
                                     @RequestBody Map<String, List<UUID>> body) {
        return playlistService.reorder(id, body.get("entryIds"));
    }

    // ---- playback settings ----

    @GetMapping("/study-materials/{materialId}/playback")
    public PlaybackSettingsResponse playback(@PathVariable UUID materialId) {
        return playbackService.get(materialId);
    }

    @PutMapping("/study-materials/{materialId}/playback")
    public PlaybackSettingsResponse savePlayback(@PathVariable UUID materialId,
                                                  @Valid @RequestBody PlaybackSettingsRequest request) {
        return playbackService.save(materialId, request);
    }
}
