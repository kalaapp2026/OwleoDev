package com.nest.app.curriculum.service;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.nest.app.curriculum.dto.PlaybackSettingsRequest;
import com.nest.app.curriculum.dto.PlaybackSettingsResponse;
import com.nest.app.curriculum.entity.MaterialPlaybackSettings;
import com.nest.app.curriculum.repository.MaterialPlaybackSettingsRepository;
import com.nest.common.exception.BadRequestException;
import com.nest.common.exception.ForbiddenException;
import com.nest.common.security.TenantContext;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.util.List;
import java.util.UUID;

/**
 * Per-person playback preferences for one track: tempo, volume, loop, and which stretches of it.
 *
 * <p>Keyed by membership as well as material, because two trainers practising the same piece want
 * different tempos. Storing one setting per track would mean each save silently undoing the
 * other's.
 */
@Service
public class MaterialPlaybackService {

    private static final BigDecimal MIN_SPEED = new BigDecimal("0.25");
    private static final BigDecimal MAX_SPEED = new BigDecimal("2.00");

    private final MaterialPlaybackSettingsRepository repository;
    private final StudyMaterialService studyMaterialService;
    private final ObjectMapper objectMapper;

    public MaterialPlaybackService(MaterialPlaybackSettingsRepository repository,
                                    StudyMaterialService studyMaterialService,
                                    ObjectMapper objectMapper) {
        this.repository = repository;
        this.studyMaterialService = studyMaterialService;
        this.objectMapper = objectMapper;
    }

    /** Defaults rather than a 404 when nothing was ever saved - the player always needs a value. */
    @Transactional(readOnly = true)
    public PlaybackSettingsResponse get(UUID materialId) {
        studyMaterialService.assertReadable(materialId);
        return repository.findByMembershipIdAndMaterialId(currentMembershipId(), materialId)
                .map(this::toResponse)
                .orElseGet(() -> new PlaybackSettingsResponse(BigDecimal.ONE, 80, false, List.of()));
    }

    @Transactional
    public PlaybackSettingsResponse save(UUID materialId, PlaybackSettingsRequest request) {
        studyMaterialService.assertReadable(materialId);
        UUID membershipId = currentMembershipId();

        MaterialPlaybackSettings settings = repository
                .findByMembershipIdAndMaterialId(membershipId, materialId)
                .orElseGet(() -> MaterialPlaybackSettings.builder()
                        .membershipId(membershipId)
                        .materialId(materialId)
                        .build());

        if (request.speed() != null) {
            settings.setSpeed(clampSpeed(request.speed()));
        }
        if (request.volume() != null) {
            settings.setVolume(Math.max(0, Math.min(100, request.volume())));
        }
        if (request.loopEnabled() != null) {
            settings.setLoopEnabled(request.loopEnabled());
        }
        if (request.segments() != null) {
            settings.setSegments(writeSegments(validate(request.segments())));
        }
        return toResponse(repository.save(settings));
    }

    // -----------------------------------------------------------------------

    /**
     * Rejects a segment that ends before it starts.
     *
     * <p>Worth failing loudly rather than clamping: such a segment plays for no time at all, so a
     * silently-accepted one looks to the user like the track is broken.
     */
    private List<PlaybackSettingsRequest.Segment> validate(List<PlaybackSettingsRequest.Segment> segments) {
        for (PlaybackSettingsRequest.Segment segment : segments) {
            if (segment.end() <= segment.start()) {
                throw new BadRequestException("A segment has to end after it starts");
            }
        }
        return segments;
    }

    /** The schema constrains this too; clamping here keeps a stray value from becoming a 500. */
    private BigDecimal clampSpeed(BigDecimal speed) {
        return speed.max(MIN_SPEED).min(MAX_SPEED);
    }

    private String writeSegments(List<PlaybackSettingsRequest.Segment> segments) {
        if (segments.isEmpty()) {
            // Null rather than "[]" so "play the whole file" is one representation, not two.
            return null;
        }
        try {
            return objectMapper.writeValueAsString(segments);
        } catch (JsonProcessingException e) {
            throw new BadRequestException("Could not store those segments");
        }
    }

    private List<PlaybackSettingsRequest.Segment> readSegments(String json) {
        if (json == null || json.isBlank()) {
            return List.of();
        }
        try {
            return objectMapper.readValue(json, new TypeReference<>() {
            });
        } catch (JsonProcessingException e) {
            // Unreadable JSON means the whole track becomes unplayable if this throws. Playing it
            // end to end is the safe degradation.
            return List.of();
        }
    }

    private PlaybackSettingsResponse toResponse(MaterialPlaybackSettings settings) {
        return new PlaybackSettingsResponse(
                settings.getSpeed(), settings.getVolume(), settings.isLoopEnabled(),
                readSegments(settings.getSegments()));
    }

    private UUID currentMembershipId() {
        return TenantContext.require().activeMembership()
                .orElseThrow(() -> new ForbiddenException("Request has no active academy membership"))
                .membershipId();
    }
}
