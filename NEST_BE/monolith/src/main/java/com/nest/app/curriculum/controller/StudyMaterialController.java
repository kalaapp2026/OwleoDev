package com.nest.app.curriculum.controller;

import com.nest.app.curriculum.dto.BatchMaterialSummary;
import com.nest.app.curriculum.dto.StudyMaterialResponse;
import com.nest.app.curriculum.dto.UpdateStudyMaterialRequest;
import com.nest.app.curriculum.entity.StudyMaterialPermission;
import com.nest.app.curriculum.service.StudyMaterialService;
import com.nest.common.security.FeatureKey;
import com.nest.common.security.RequiresFeature;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

import java.util.List;
import java.util.UUID;

@RestController
@Tag(name = "Study Material")
public class StudyMaterialController {

    private final StudyMaterialService studyMaterialService;

    public StudyMaterialController(StudyMaterialService studyMaterialService) {
        this.studyMaterialService = studyMaterialService;
    }

    /**
     * The home screen - every batch whose material this caller can see, with its file count.
     *
     * <p>Deliberately not gated by {@code @RequiresFeature}. It was, until Course Materials merged
     * in and made this the one materials feature: the tile is now open to students, and a student
     * holds no course grants at all, so the annotation would 403 exactly the people the screen
     * exists for. The service scopes the list instead - editors by grant, readers by the batches
     * they belong to or teach.
     */
    @GetMapping("/study-materials/batches")
    public List<BatchMaterialSummary> batchSummaries() {
        return studyMaterialService.batchSummaries();
    }

    /** Deliberately not gated by @RequiresFeature: a student reading their own batch's material
     * holds no course grants at all. The service checks batch membership instead. */
    @GetMapping("/batches/{batchId}/study-materials")
    public List<StudyMaterialResponse> listForBatch(@PathVariable UUID batchId) {
        return studyMaterialService.listForBatch(batchId);
    }

    @PostMapping("/batches/{batchId}/study-materials")
    @RequiresFeature(FeatureKey.SYLLABUS_EDIT)
    public StudyMaterialResponse upload(
            @PathVariable UUID batchId,
            @RequestParam("file") MultipartFile file,
            @RequestParam(required = false) String title,
            @RequestParam(required = false) String description,
            @RequestParam(required = false) StudyMaterialPermission permission) {
        return studyMaterialService.upload(batchId, file, title, description, permission);
    }

    @PutMapping("/study-materials/{id}")
    @RequiresFeature(FeatureKey.SYLLABUS_EDIT)
    public StudyMaterialResponse update(@PathVariable UUID id,
                                         @Valid @RequestBody UpdateStudyMaterialRequest request) {
        return studyMaterialService.update(id, request);
    }

    @DeleteMapping("/study-materials/{id}")
    @RequiresFeature(FeatureKey.SYLLABUS_EDIT)
    public void delete(@PathVariable UUID id) {
        studyMaterialService.delete(id);
    }
}
