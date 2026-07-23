package com.nest.app.curriculum.controller;

import com.nest.app.curriculum.dto.MaterialAttachmentResponse;
import com.nest.app.curriculum.dto.SyllabusUnitRequest;
import com.nest.app.curriculum.dto.SyllabusUnitResponse;
import com.nest.app.curriculum.dto.TrackResponse;
import com.nest.app.curriculum.dto.UpdateSyllabusUnitRequest;
import com.nest.app.curriculum.entity.SyllabusUnitStatus;
import com.nest.app.curriculum.service.SyllabusService;
import com.nest.common.security.FeatureKey;
import com.nest.common.security.RequiresFeature;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

import java.util.List;
import java.util.UUID;

@RestController
@Tag(name = "Syllabus")
public class SyllabusController {

    private final SyllabusService syllabusService;

    public SyllabusController(SyllabusService syllabusService) {
        this.syllabusService = syllabusService;
    }

    @PostMapping("/syllabus-units")
    @RequiresFeature(FeatureKey.SYLLABUS_EDIT)
    public SyllabusUnitResponse createUnit(@Valid @RequestBody SyllabusUnitRequest request) {
        return syllabusService.createUnit(request);
    }

    @PutMapping("/syllabus-units/{id}")
    @RequiresFeature(FeatureKey.SYLLABUS_EDIT)
    public SyllabusUnitResponse updateUnit(@PathVariable UUID id, @Valid @RequestBody UpdateSyllabusUnitRequest request) {
        return syllabusService.updateUnit(id, request);
    }

    @DeleteMapping("/syllabus-units/{id}")
    @RequiresFeature(FeatureKey.SYLLABUS_EDIT)
    public void deleteUnit(@PathVariable UUID id) {
        syllabusService.deleteUnit(id);
    }

    /** A unit can carry several PDF/image attachments - each call adds one more, separate from
     * create/update since a file can't ride along with a JSON body (same reasoning as the
     * profile-picture upload). */
    @PostMapping("/syllabus-units/{id}/materials")
    @RequiresFeature(FeatureKey.SYLLABUS_EDIT)
    public MaterialAttachmentResponse addAttachment(@PathVariable UUID id, @RequestParam("file") MultipartFile file) {
        return syllabusService.addAttachment(id, file);
    }

    @GetMapping("/syllabus-units/{id}/materials")
    public List<MaterialAttachmentResponse> listAttachments(@PathVariable UUID id) {
        return syllabusService.listAttachments(id);
    }

    @DeleteMapping("/syllabus-units/{id}/materials/{attachmentId}")
    @RequiresFeature(FeatureKey.SYLLABUS_EDIT)
    public void deleteAttachment(@PathVariable UUID id, @PathVariable UUID attachmentId) {
        syllabusService.deleteAttachment(id, attachmentId);
    }

    /** membershipId narrows the result to what THAT membership can actually see (course-wide
     * material they're enrolled for, plus batch-targeted material for batches they're in or
     * teach) - omitted, this is the Admin/Trainer management view showing everything. */
    @GetMapping("/courses/{courseId}/syllabus-units")
    public List<SyllabusUnitResponse> listForCourse(@PathVariable UUID courseId, @RequestParam(required = false) UUID membershipId) {
        return syllabusService.listForCourse(courseId, membershipId);
    }

    @PatchMapping("/syllabus-units/{id}/status")
    @RequiresFeature(FeatureKey.SYLLABUS_EDIT)
    public SyllabusUnitResponse setStatus(@PathVariable UUID id, @RequestParam SyllabusUnitStatus status) {
        return syllabusService.setUnitStatus(id, status);
    }

    /** A song attachment - title/streamOnly alongside the audio file in one multipart call,
     * unlike the PDF/image attachment there's no standalone Track worth having without its file. */
    @PostMapping("/syllabus-units/{id}/tracks")
    @RequiresFeature(FeatureKey.SYLLABUS_EDIT)
    public TrackResponse addTrack(@PathVariable UUID id, @RequestParam String title,
                                   @RequestParam(defaultValue = "true") boolean streamOnly,
                                   @RequestParam("file") MultipartFile file) {
        return syllabusService.addTrack(id, title, streamOnly, file);
    }

    @GetMapping("/syllabus-units/{id}/tracks")
    public List<TrackResponse> listTracks(@PathVariable UUID id) {
        return syllabusService.listTracks(id);
    }

    @DeleteMapping("/syllabus-units/{id}/tracks/{trackId}")
    @RequiresFeature(FeatureKey.SYLLABUS_EDIT)
    public void deleteTrack(@PathVariable UUID id, @PathVariable UUID trackId) {
        syllabusService.deleteTrack(id, trackId);
    }
}
