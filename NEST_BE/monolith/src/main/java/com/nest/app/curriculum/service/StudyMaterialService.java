package com.nest.app.curriculum.service;

import com.nest.app.curriculum.dto.BatchMaterialSummary;
import com.nest.app.curriculum.dto.StudyMaterialResponse;
import com.nest.app.curriculum.dto.UpdateStudyMaterialRequest;
import com.nest.app.curriculum.entity.Course;
import com.nest.app.curriculum.entity.StudyMaterial;
import com.nest.app.curriculum.entity.StudyMaterialPermission;
import com.nest.app.curriculum.entity.StudyMaterialType;
import com.nest.app.curriculum.repository.CourseRepository;
import com.nest.app.curriculum.repository.StudyMaterialRepository;
import com.nest.app.enrolment.entity.Batch;
import com.nest.app.enrolment.repository.BatchMemberRepository;
import com.nest.app.enrolment.repository.BatchRepository;
import com.nest.app.identity.entity.User;
import com.nest.app.identity.repository.UserRepository;
import com.nest.app.identity.service.CourseFeatureGuard;
import com.nest.app.storage.FileStorageService;
import com.nest.common.audit.Auditable;
import com.nest.common.exception.ForbiddenException;
import com.nest.common.exception.ResourceNotFoundException;
import com.nest.common.security.FeatureKey;
import com.nest.common.security.Role;
import com.nest.common.security.TenantContext;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.multipart.MultipartFile;

import java.time.Instant;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;

/**
 * Files shared with a batch (PRD 3.9).
 *
 * <p>Two access questions, deliberately kept apart. <em>Managing</em> material needs the
 * SYLLABUS_EDIT grant on the batch's course - that is Admin/Trainer territory. <em>Seeing</em> it
 * needs only batch membership, because the whole point is that students can read what was shared
 * with their class.
 */
@Service
public class StudyMaterialService {

    /** Deliberately wider than the syllabus attachment set: this feature exists to share audio
     * (backing tracks, rhythm cues) as much as documents. */
    private static final Set<String> ALLOWED_CONTENT_TYPES = Set.of(
            "application/pdf",
            "application/msword",
            "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
            "application/vnd.ms-powerpoint",
            "application/vnd.openxmlformats-officedocument.presentationml.presentation",
            "application/vnd.ms-excel",
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            "text/plain",
            "image/jpeg", "image/png", "image/gif", "image/webp",
            "audio/mpeg", "audio/mp3", "audio/wav", "audio/x-wav",
            "audio/mp4", "audio/aac", "audio/ogg",
            // Some browsers send this for mp3/m4a rather than a real audio type; the extension
            // check in StudyMaterialType is what actually classifies the file.
            "application/octet-stream");

    private static final long MAX_BYTES = 25L * 1024 * 1024;

    private final StudyMaterialRepository studyMaterialRepository;
    private final BatchRepository batchRepository;
    private final BatchMemberRepository batchMemberRepository;
    private final CourseRepository courseRepository;
    private final UserRepository userRepository;
    private final FileStorageService fileStorageService;
    private final CourseFeatureGuard courseFeatureGuard;

    public StudyMaterialService(StudyMaterialRepository studyMaterialRepository,
                                 BatchRepository batchRepository,
                                 BatchMemberRepository batchMemberRepository,
                                 CourseRepository courseRepository,
                                 UserRepository userRepository,
                                 FileStorageService fileStorageService,
                                 CourseFeatureGuard courseFeatureGuard) {
        this.studyMaterialRepository = studyMaterialRepository;
        this.batchRepository = batchRepository;
        this.batchMemberRepository = batchMemberRepository;
        this.courseRepository = courseRepository;
        this.userRepository = userRepository;
        this.fileStorageService = fileStorageService;
        this.courseFeatureGuard = courseFeatureGuard;
    }

    /**
     * The home screen: every batch whose material this caller can see, with its file count.
     *
     * <p>Two populations reach this, and they are scoped differently. Someone who can EDIT
     * material sees the batches they hold SYLLABUS_EDIT on - per course, so a trainer granted one
     * course does not survey the academy. Everyone else is a READER: a student opening their own
     * class's files, or a trainer who teaches a batch without holding the edit grant. They see the
     * batches they actually belong to.
     *
     * <p>Before the Course Materials merge this method was edit-only, because the feature was
     * gated behind SYLLABUS_EDIT at the tile. It no longer is - reading is the common case - so
     * scoping readers by a grant they were never meant to hold would show them an empty screen.
     */
    @Transactional(readOnly = true)
    public List<BatchMaterialSummary> batchSummaries() {
        var visible = courseFeatureGuard.visibleCourseIds(FeatureKey.SYLLABUS_EDIT);

        Map<UUID, Course> coursesById = courseRepository
                .findByAcademyIdOrderByNameAsc(TenantContext.currentAcademyId()).stream()
                .filter(c -> visible.isEmpty() || visible.get().contains(c.getId()))
                .collect(Collectors.toMap(Course::getId, c -> c));

        List<Batch> batches;
        if (coursesById.isEmpty()) {
            // No edit grant anywhere: fall back to the reader's own batches. An empty course map
            // means "can edit nothing", not "can see nothing".
            batches = readableBatches();
            if (batches.isEmpty()) {
                return List.of();
            }
            coursesById = courseRepository
                    .findAllById(batches.stream().map(Batch::getCourseId).collect(Collectors.toSet()))
                    .stream()
                    // Cross-academy safety: a stale membership must not drag another academy's
                    // course into this list.
                    .filter(c -> c.getAcademyId().equals(TenantContext.currentAcademyId()))
                    .collect(Collectors.toMap(Course::getId, c -> c));
            final Map<UUID, Course> resolved = coursesById;
            batches = batches.stream()
                    .filter(b -> resolved.containsKey(b.getCourseId()))
                    .toList();
        } else {
            batches = batchRepository.findByCourseIdIn(coursesById.keySet());
        }

        if (batches.isEmpty()) {
            return List.of();
        }

        Map<UUID, Integer> counts = new HashMap<>();
        Map<UUID, Instant> latest = new HashMap<>();
        for (StudyMaterial material : studyMaterialRepository
                .findByBatchIdIn(batches.stream().map(Batch::getId).toList())) {
            counts.merge(material.getBatchId(), 1, Integer::sum);
            latest.merge(material.getBatchId(), material.getUploadedAt(),
                    (a, b) -> a.isAfter(b) ? a : b);
        }

        List<BatchMaterialSummary> result = new ArrayList<>();
        for (Batch batch : batches) {
            Course course = coursesById.get(batch.getCourseId());
            result.add(new BatchMaterialSummary(
                    batch.getId(), batch.getName(),
                    course == null ? null : course.getId(),
                    course == null ? null : course.getName(),
                    course == null ? null : course.getIconKey(),
                    course == null ? null : course.getCategory(),
                    batch.getStatus(),
                    counts.getOrDefault(batch.getId(), 0),
                    latest.get(batch.getId())));
        }
        return result;
    }

    /**
     * One batch's files, newest first.
     *
     * <p>Readable by anyone in the batch, not just whoever can edit it - a student opening their
     * own class's material is the common case, and gating this on SYLLABUS_EDIT would lock them
     * out of the thing the feature exists to give them.
     */
    @Transactional(readOnly = true)
    public List<StudyMaterialResponse> listForBatch(UUID batchId) {
        assertCanView(batchId);
        List<StudyMaterial> materials = studyMaterialRepository.findByBatchIdOrderByUploadedAtDesc(batchId);
        return toResponses(materials);
    }

    @Transactional
    @Auditable(action = "STUDY_MATERIAL_UPLOADED", entityType = "study_material")
    public StudyMaterialResponse upload(UUID batchId, MultipartFile file, String title,
                                         String description, StudyMaterialPermission permission) {
        assertCanManage(batchId);

        String originalName = file.getOriginalFilename() == null
                ? "file" : file.getOriginalFilename();
        String url = fileStorageService.store(file, "study-materials", ALLOWED_CONTENT_TYPES, MAX_BYTES);
        StudyMaterialType fileType = StudyMaterialType.fromFileName(originalName);

        StudyMaterial material = studyMaterialRepository.save(StudyMaterial.builder()
                .batchId(batchId)
                .title(title == null || title.isBlank() ? titleFromFileName(originalName) : title.trim())
                .description(description == null || description.isBlank() ? null : description.trim())
                .url(url)
                .fileName(originalName)
                .contentType(file.getContentType())
                .fileType(fileType)
                .sizeBytes(file.getSize())
                // Audio defaults to view-only: a backing track is the file most likely to be
                // redistributed, and the admin can still switch it on the form.
                .permission(permission != null ? permission
                        : fileType == StudyMaterialType.AUDIO
                                ? StudyMaterialPermission.VIEW_ONLY
                                : StudyMaterialPermission.DOWNLOADABLE)
                .uploadedBy(TenantContext.currentUserId())
                .build());

        return toResponses(List.of(material)).get(0);
    }

    @Transactional
    @Auditable(action = "STUDY_MATERIAL_UPDATED", entityType = "study_material")
    public StudyMaterialResponse update(UUID materialId, UpdateStudyMaterialRequest request) {
        StudyMaterial material = findOrThrow(materialId);
        assertCanManage(material.getBatchId());

        material.setTitle(request.title().trim());
        material.setDescription(
                request.description() == null || request.description().isBlank()
                        ? null : request.description().trim());
        material.setPermission(request.permission());
        return toResponses(List.of(studyMaterialRepository.save(material))).get(0);
    }

    @Transactional
    @Auditable(action = "STUDY_MATERIAL_DELETED", entityType = "study_material")
    public void delete(UUID materialId) {
        StudyMaterial material = findOrThrow(materialId);
        assertCanManage(material.getBatchId());
        // The stored file is deliberately left on disk. Another material row could reference the
        // same upload, and an orphaned blob is a cheaper problem than a broken link on a file
        // someone else is still sharing.
        studyMaterialRepository.delete(material);
    }

    /** Managing needs SYLLABUS_EDIT on the batch's course. */
    private void assertCanManage(UUID batchId) {
        Batch batch = batchRepository.findById(batchId)
                .orElseThrow(() -> new ResourceNotFoundException("Batch not found: " + batchId));
        courseFeatureGuard.assertCourseFeature(batch.getCourseId(), FeatureKey.SYLLABUS_EDIT);
    }

    /**
     * Viewing needs either the manage grant or membership of the batch.
     *
     * <p>Checked in that order because the common reader is a student, and a student holds no
     * course grants at all - asking the grant question first and stopping there is exactly how
     * this feature would lock out the people it exists for.
     */
    /**
     * The batches a reader can open material for: the ones they are enrolled in, plus the ones
     * they teach.
     *
     * <p>The list counterpart of the last two branches of {@link #assertCanView} - the same two
     * routes in, so the home screen cannot offer a batch that opening would then 403 on, nor hide
     * one that opening would allow.
     */
    private List<Batch> readableBatches() {
        var membership = TenantContext.require().activeMembership().orElse(null);
        if (membership == null) {
            return List.of();
        }
        Set<UUID> batchIds = new HashSet<>();
        batchMemberRepository.findByMembershipId(membership.membershipId())
                .forEach(bm -> batchIds.add(bm.getBatchId()));
        batchRepository.findByTrainerMembershipId(membership.membershipId())
                .forEach(b -> batchIds.add(b.getId()));
        return batchIds.isEmpty() ? List.of() : batchRepository.findAllById(batchIds);
    }

    private void assertCanView(UUID batchId) {
        Batch batch = batchRepository.findById(batchId)
                .orElseThrow(() -> new ResourceNotFoundException("Batch not found: " + batchId));

        if (courseFeatureGuard.hasCourseFeature(batch.getCourseId(), FeatureKey.SYLLABUS_EDIT)) {
            return;
        }
        var principal = TenantContext.require();
        var membership = principal.activeMembership()
                .orElseThrow(() -> new ForbiddenException("Request has no active academy membership"));
        // A trainer who teaches the batch but wasn't granted syllabus editing can still read it.
        if (membership.roleType() == Role.TRAINER
                && membership.membershipId().equals(batch.getTrainerMembershipId())) {
            return;
        }
        if (batchMemberRepository.existsByBatchIdAndMembershipId(batchId, membership.membershipId())) {
            return;
        }
        throw new ForbiddenException("This material belongs to a batch you're not part of");
    }

    private StudyMaterial findOrThrow(UUID id) {
        return studyMaterialRepository.findById(id)
                .orElseThrow(() -> new ResourceNotFoundException("Material not found: " + id));
    }

    /** "chord-chart-week1.pdf" -> "chord chart week1", so an upload without a typed title still
     * reads as something rather than showing a filename with a extension. */
    private String titleFromFileName(String fileName) {
        String withoutExtension = fileName.replaceAll("\\.[^.]+$", "");
        String spaced = withoutExtension.replaceAll("[-_]+", " ").replaceAll("\\s+", " ").trim();
        return spaced.isEmpty() ? fileName : spaced;
    }

    private List<StudyMaterialResponse> toResponses(List<StudyMaterial> materials) {
        if (materials.isEmpty()) {
            return List.of();
        }
        Map<UUID, String> namesByUser = userRepository
                .findAllById(materials.stream().map(StudyMaterial::getUploadedBy)
                        .collect(Collectors.toSet()))
                .stream().collect(Collectors.toMap(User::getId, User::getFullName));

        return materials.stream()
                .map(m -> new StudyMaterialResponse(
                        m.getId(), m.getBatchId(), m.getTitle(), m.getDescription(),
                        m.getUrl(), m.getFileName(), m.getContentType(), m.getFileType(),
                        m.getSizeBytes(), m.getPermission(), m.getUploadedBy(),
                        namesByUser.get(m.getUploadedBy()), m.getUploadedAt()))
                .collect(Collectors.toList());
    }
}
