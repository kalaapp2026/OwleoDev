package com.nest.app.curriculum.service;

import com.nest.app.curriculum.dto.BatchMaterialSummary;
import com.nest.app.curriculum.dto.CourseMaterialSummary;
import com.nest.app.curriculum.dto.StudyMaterialResponse;
import com.nest.app.curriculum.dto.UpdateStudyMaterialRequest;
import com.nest.app.curriculum.entity.Course;
import com.nest.app.curriculum.entity.MaterialTarget;
import com.nest.app.curriculum.entity.StudyMaterial;
import com.nest.app.curriculum.entity.StudyMaterialPermission;
import com.nest.app.curriculum.entity.StudyMaterialStudent;
import com.nest.app.curriculum.entity.StudyMaterialTargetType;
import com.nest.app.curriculum.entity.StudyMaterialType;
import com.nest.app.curriculum.entity.StudyMaterialVisibility;
import com.nest.app.curriculum.repository.CourseRepository;
import com.nest.app.curriculum.repository.MaterialPlaylistEntryRepository;
import com.nest.app.curriculum.repository.StudyMaterialRepository;
import com.nest.app.curriculum.repository.StudyMaterialStudentRepository;
import com.nest.app.enrolment.entity.Batch;
import com.nest.app.enrolment.entity.BatchMember;
import com.nest.app.enrolment.entity.BatchTrainer;
import com.nest.app.enrolment.repository.BatchMemberRepository;
import com.nest.app.enrolment.repository.BatchRepository;
import com.nest.app.enrolment.repository.BatchTrainerRepository;
import com.nest.app.identity.entity.CourseMap;
import com.nest.app.identity.entity.User;
import com.nest.app.identity.repository.CourseMapRepository;
import com.nest.app.identity.repository.UserRepository;
import com.nest.app.identity.service.CourseFeatureGuard;
import com.nest.app.storage.FileStorageService;
import com.nest.common.audit.Auditable;
import com.nest.common.exception.BadRequestException;
import com.nest.common.exception.ForbiddenException;
import com.nest.common.exception.ResourceNotFoundException;
import com.nest.common.security.FeatureKey;
import com.nest.common.security.TenantContext;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.multipart.MultipartFile;

import java.time.Instant;
import java.util.ArrayList;
import java.util.Collection;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;

/**
 * Files shared with an audience (PRD 3.9): whole courses, batches, or both.
 *
 * <p>A file is aimed at courses (every student actively enrolled in them gets it, whether or not
 * they sit in a batch) and/or batches (the students in them), and can be narrowed to chosen students
 * on top. Three questions are kept apart:
 * <ul>
 *   <li><b>Managing</b> (upload to, edit, delete) needs SYLLABUS_EDIT on EVERY course the file
 *       reaches - a trainer holding Basic cannot reshape a file that also goes to Advanced.</li>
 *   <li><b>Opening as staff</b> needs SYLLABUS_EDIT on at least one of them.</li>
 *   <li><b>Opening as a reader</b> needs being in the audience: enrolled in a targeted course, or
 *       sitting in (or teaching) a targeted batch - and, for a file narrowed to chosen students, being
 *       named.</li>
 * </ul>
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

    /** Stands in for an empty id list in an IN clause, which not every dialect accepts. */
    private static final UUID NONE = new UUID(0L, 0L);

    private final StudyMaterialRepository studyMaterialRepository;
    private final BatchRepository batchRepository;
    private final BatchMemberRepository batchMemberRepository;
    private final BatchTrainerRepository batchTrainerRepository;
    private final CourseRepository courseRepository;
    private final CourseMapRepository courseMapRepository;
    private final UserRepository userRepository;
    private final FileStorageService fileStorageService;
    private final CourseFeatureGuard courseFeatureGuard;
    private final StudyMaterialStudentRepository studyMaterialStudentRepository;
    private final MaterialPlaylistEntryRepository playlistEntryRepository;

    public StudyMaterialService(StudyMaterialRepository studyMaterialRepository,
                                 BatchRepository batchRepository,
                                 BatchMemberRepository batchMemberRepository,
                                 BatchTrainerRepository batchTrainerRepository,
                                 CourseRepository courseRepository,
                                 CourseMapRepository courseMapRepository,
                                 UserRepository userRepository,
                                 FileStorageService fileStorageService,
                                 CourseFeatureGuard courseFeatureGuard,
                                 StudyMaterialStudentRepository studyMaterialStudentRepository,
                                 MaterialPlaylistEntryRepository playlistEntryRepository) {
        this.studyMaterialRepository = studyMaterialRepository;
        this.batchRepository = batchRepository;
        this.batchMemberRepository = batchMemberRepository;
        this.batchTrainerRepository = batchTrainerRepository;
        this.courseRepository = courseRepository;
        this.courseMapRepository = courseMapRepository;
        this.userRepository = userRepository;
        this.fileStorageService = fileStorageService;
        this.courseFeatureGuard = courseFeatureGuard;
        this.studyMaterialStudentRepository = studyMaterialStudentRepository;
        this.playlistEntryRepository = playlistEntryRepository;
    }

    // ------------------------------------------------------------------------------------------
    // Who the caller is, and what that lets them do with a material
    // ------------------------------------------------------------------------------------------

    /** What ties the caller to batches and courses as a PARTICIPANT (as opposed to as staff). */
    private record Caller(UUID membershipId, Set<UUID> memberBatches, Set<UUID> teachingBatches,
                          Set<UUID> enrolledCourses) {
    }

    private Caller caller() {
        var membership = TenantContext.require().activeMembership().orElse(null);
        if (membership == null) {
            return new Caller(null, Set.of(), Set.of(), Set.of());
        }
        UUID me = membership.membershipId();
        Set<UUID> memberBatches = batchMemberRepository.findByMembershipId(me).stream()
                .map(BatchMember::getBatchId).collect(Collectors.toSet());
        Set<UUID> teaching = new HashSet<>();
        batchRepository.findByTrainerMembershipId(me).forEach(b -> teaching.add(b.getId()));
        batchTrainerRepository.findByTrainerMembershipId(me).forEach(bt -> teaching.add(bt.getBatchId()));
        Set<UUID> enrolled = courseMapRepository.findByMembershipId(me).stream()
                .filter(CourseMap::isActive).map(CourseMap::getCourseId).collect(Collectors.toSet());
        return new Caller(me, memberBatches, teaching, enrolled);
    }

    /**
     * Answers "may this caller manage / open this material" for a set of materials, loading what it
     * needs once and remembering per-course answers so a long list costs a handful of queries.
     */
    private final class Access {
        final Caller me;
        final Map<UUID, Batch> batches;
        final Set<UUID> sharedWithMe;
        private final Map<UUID, Boolean> editsCourse = new HashMap<>();
        private final Map<UUID, Boolean> wholeCourse = new HashMap<>();

        Access(Collection<StudyMaterial> materials) {
            this.me = caller();
            this.batches = batchesOf(materials);
            List<UUID> restricted = materials.stream()
                    .filter(m -> m.getVisibility() == StudyMaterialVisibility.SELECTED)
                    .map(StudyMaterial::getId).toList();
            if (restricted.isEmpty() || me.membershipId() == null) {
                this.sharedWithMe = Set.of();
            } else {
                // One query for every restricted material rather than one per material.
                this.sharedWithMe = studyMaterialStudentRepository.findByMaterialIdIn(restricted).stream()
                        .filter(r -> r.getMembershipId().equals(me.membershipId()))
                        .map(StudyMaterialStudent::getMaterialId)
                        .collect(Collectors.toSet());
            }
        }

        boolean holdsEdit(UUID courseId) {
            return editsCourse.computeIfAbsent(courseId,
                    id -> courseFeatureGuard.hasCourseFeature(id, FeatureKey.SYLLABUS_EDIT));
        }

        /** Holds the edit grant on the course AND was not limited to only some of its batches. */
        boolean holdsWholeCourse(UUID courseId) {
            return wholeCourse.computeIfAbsent(courseId,
                    id -> holdsEdit(id) && courseFeatureGuard.batchScope(id).isEmpty());
        }

        boolean canManage(StudyMaterial m) {
            return manageProblem(m.getTargets(), batches) == null;
        }

        /** Staff access: the edit grant on at least one course the file reaches. */
        boolean isStaffFor(StudyMaterial m) {
            for (MaterialTarget t : m.getTargets()) {
                if (t.isCourse()) {
                    if (holdsWholeCourse(t.getTargetId())) {
                        return true;
                    }
                } else {
                    Batch b = batches.get(t.getTargetId());
                    if (b != null && courseFeatureGuard.batchAccessible(
                            b.allCourseIds(), b.getId(), FeatureKey.SYLLABUS_EDIT)) {
                        return true;
                    }
                }
            }
            return false;
        }

        boolean canSee(StudyMaterial m) {
            if (isStaffFor(m)) {
                return true;
            }
            if (me.membershipId() == null) {
                return false;
            }
            boolean inAudience = false;
            boolean teaches = false;
            for (MaterialTarget t : m.getTargets()) {
                if (t.isCourse()) {
                    inAudience |= me.enrolledCourses().contains(t.getTargetId());
                } else {
                    inAudience |= me.memberBatches().contains(t.getTargetId());
                    if (me.teachingBatches().contains(t.getTargetId())) {
                        inAudience = true;
                        teaches = true;
                    }
                }
            }
            if (!inAudience) {
                return false;
            }
            // A file narrowed to chosen students is for those students; whoever runs the class still sees it.
            return m.getVisibility() != StudyMaterialVisibility.SELECTED || teaches || sharedWithMe.contains(m.getId());
        }
    }

    /**
     * Why the caller may NOT manage an audience, or null when they may. Managing needs the edit grant on
     * every course reached; a whole-course target also needs the caller not to be limited to some batches
     * of it, and a batch target needs the batch within the batches they were given.
     */
    private String manageProblem(Collection<MaterialTarget> targets, Map<UUID, Batch> batches) {
        if (targets.isEmpty()) {
            return "This material has no audience";
        }
        String missingGrant = "You don't have the 'SYLLABUS_EDIT' permission for every course this material reaches";
        for (MaterialTarget t : targets) {
            if (t.isCourse()) {
                UUID courseId = t.getTargetId();
                if (!courseFeatureGuard.hasCourseFeature(courseId, FeatureKey.SYLLABUS_EDIT)) {
                    return missingGrant;
                }
                if (courseFeatureGuard.batchScope(courseId).isPresent()) {
                    return "You were given only some batches of that course, so you can't share with all of it";
                }
            } else {
                Batch batch = batches.get(t.getTargetId());
                if (batch == null) {
                    continue;
                }
                for (UUID courseId : batch.allCourseIds()) {
                    if (!courseFeatureGuard.hasCourseFeature(courseId, FeatureKey.SYLLABUS_EDIT)) {
                        return missingGrant;
                    }
                    if (!CourseFeatureGuard.inScope(courseFeatureGuard.batchScope(courseId), batch.getId())) {
                        return "That batch is outside the batches you were given";
                    }
                }
            }
        }
        return null;
    }

    private Map<UUID, Batch> batchesOf(Collection<StudyMaterial> materials) {
        Set<UUID> ids = materials.stream().flatMap(m -> m.getTargets().stream())
                .filter(MaterialTarget::isBatch).map(MaterialTarget::getTargetId)
                .collect(Collectors.toSet());
        return batchesById(ids);
    }

    private Map<UUID, Batch> batchesById(Collection<UUID> ids) {
        if (ids.isEmpty()) {
            return Map.of();
        }
        return batchRepository.findAllById(ids).stream().collect(Collectors.toMap(Batch::getId, b -> b));
    }

    /** Every course a material reaches: the courses it names plus the courses of the batches it names. */
    private static Set<UUID> coursesOf(StudyMaterial material, Map<UUID, Batch> batches) {
        Set<UUID> out = new LinkedHashSet<>();
        for (MaterialTarget t : material.getTargets()) {
            if (t.isCourse()) {
                out.add(t.getTargetId());
            } else {
                Batch b = batches.get(t.getTargetId());
                if (b != null) {
                    out.addAll(b.allCourseIds());
                }
            }
        }
        return out;
    }

    // ------------------------------------------------------------------------------------------
    // Browsing
    // ------------------------------------------------------------------------------------------

    /**
     * The home screen's batches: every batch whose material this caller can see, with its file count.
     *
     * <p>Two populations reach this, scoped differently. Someone who can EDIT material sees the batches of
     * the courses they hold SYLLABUS_EDIT on, limited to the batches they were given. Everyone else is a
     * READER - a student opening their own class's files, or a trainer who teaches a batch without the
     * edit grant - and sees the batches they actually belong to.
     *
     * <p>A batch's count includes the files aimed at the batch itself AND those aimed at any course it
     * spans that the caller can open.
     */
    @Transactional(readOnly = true)
    public List<BatchMaterialSummary> batchSummaries() {
        var visible = courseFeatureGuard.visibleCourseIds(FeatureKey.SYLLABUS_EDIT);
        UUID academyId = TenantContext.currentAcademyId();

        Set<UUID> editorCourseIds = courseRepository.findByAcademyIdOrderByNameAsc(academyId).stream()
                .map(Course::getId)
                .filter(id -> visible.isEmpty() || visible.get().contains(id))
                .collect(Collectors.toSet());

        List<Batch> batches;
        if (editorCourseIds.isEmpty()) {
            // No edit grant anywhere: fall back to the reader's own batches. An empty course set
            // means "can edit nothing", not "can see nothing".
            batches = readableBatches();
        } else {
            // Only the batches this editor was given within each course; a batch spanning several is
            // listed once, through any course of it they hold.
            Map<UUID, Optional<Set<UUID>>> scopes = new HashMap<>();
            batches = batchRepository.findByCourseIdIn(editorCourseIds).stream()
                    .filter(b -> b.allCourseIds().stream().filter(editorCourseIds::contains).anyMatch(c ->
                            CourseFeatureGuard.inScope(scopes.computeIfAbsent(c, courseFeatureGuard::batchScope), b.getId())))
                    .toList();
        }
        if (batches.isEmpty()) {
            return List.of();
        }

        Set<UUID> allCourseIds = batches.stream().flatMap(b -> b.allCourseIds().stream())
                .collect(Collectors.toCollection(LinkedHashSet::new));
        Map<UUID, Course> coursesById = courseRepository.findAllById(allCourseIds).stream()
                // Cross-academy safety: a stale membership must not drag another academy's course in.
                .filter(c -> academyId.equals(c.getAcademyId()))
                .collect(Collectors.toMap(Course::getId, c -> c));
        batches = batches.stream().filter(b -> coursesById.containsKey(b.getCourseId())).toList();
        if (batches.isEmpty()) {
            return List.of();
        }

        List<StudyMaterial> candidates = studyMaterialRepository.findForTargets(
                batches.stream().map(Batch::getId).toList(), orNone(allCourseIds));
        Access access = new Access(candidates);
        List<StudyMaterial> seen = candidates.stream().filter(access::canSee).toList();

        List<BatchMaterialSummary> result = new ArrayList<>();
        for (Batch batch : batches) {
            List<StudyMaterial> forBatch = seen.stream()
                    .filter(m -> m.getTargets().stream().anyMatch(t -> t.isBatch()
                            ? t.getTargetId().equals(batch.getId())
                            : batch.coversCourse(t.getTargetId())))
                    .toList();
            Course course = coursesById.get(batch.getCourseId());
            result.add(new BatchMaterialSummary(
                    batch.getId(), batch.getName(),
                    course.getId(), course.getName(), course.getIconKey(), course.getCategory(),
                    batch.getStatus(),
                    forBatch.size(),
                    batch.allCourseIds().stream().filter(coursesById::containsKey).toList(),
                    batch.allCourseIds().stream().map(id -> coursesById.get(id)).filter(java.util.Objects::nonNull)
                            .map(Course::getName).toList(),
                    forBatch.stream().map(StudyMaterial::getUploadedAt).max(Comparator.naturalOrder()).orElse(null)));
        }
        return result;
    }

    /**
     * The home screen's courses: every course whose files this caller can browse as a whole - the ones
     * they may edit material for, and the ones they are enrolled in - with how many files reach it.
     */
    @Transactional(readOnly = true)
    public List<CourseMaterialSummary> courseSummaries() {
        UUID academyId = TenantContext.currentAcademyId();
        var visible = courseFeatureGuard.visibleCourseIds(FeatureKey.SYLLABUS_EDIT);
        Caller me = caller();

        List<Course> courses = courseRepository.findByAcademyIdOrderByNameAsc(academyId).stream()
                .filter(c -> (visible.isEmpty() || visible.get().contains(c.getId())) || me.enrolledCourses().contains(c.getId()))
                .toList();
        if (courses.isEmpty()) {
            return List.of();
        }
        Set<UUID> courseIds = courses.stream().map(Course::getId).collect(Collectors.toSet());
        Set<UUID> batchIds = batchRepository.findByCourseIdIn(courseIds).stream()
                .map(Batch::getId).collect(Collectors.toSet());

        List<StudyMaterial> candidates = studyMaterialRepository.findForTargets(orNone(batchIds), courseIds);
        Access access = new Access(candidates);
        List<StudyMaterial> seen = candidates.stream().filter(access::canSee).toList();

        List<CourseMaterialSummary> result = new ArrayList<>();
        for (Course course : courses) {
            List<StudyMaterial> forCourse = seen.stream()
                    .filter(m -> coursesOf(m, access.batches).contains(course.getId()))
                    .toList();
            result.add(new CourseMaterialSummary(course.getId(), course.getName(), course.getIconKey(),
                    course.getCategory(), forCourse.size(),
                    forCourse.stream().map(StudyMaterial::getUploadedAt).max(Comparator.naturalOrder()).orElse(null)));
        }
        return result;
    }

    /**
     * One batch's files, newest first: those aimed at the batch and those aimed at a course it spans -
     * minus any the caller cannot open.
     */
    @Transactional(readOnly = true)
    public List<StudyMaterialResponse> listForBatch(UUID batchId) {
        Batch batch = batchRepository.findById(batchId)
                .orElseThrow(() -> new ResourceNotFoundException("Batch not found: " + batchId));
        assertCanViewBatch(batch);
        List<StudyMaterial> candidates = studyMaterialRepository.findForTargets(
                Set.of(batchId), orNone(batch.allCourseIds()));
        return respondVisible(candidates);
    }

    /** One course's files: aimed at the whole course, or at a batch that covers it. */
    @Transactional(readOnly = true)
    public List<StudyMaterialResponse> listForCourse(UUID courseId) {
        Course course = courseRepository.findById(courseId)
                .orElseThrow(() -> new ResourceNotFoundException("Course not found: " + courseId));
        if (!course.getAcademyId().equals(TenantContext.currentAcademyId())) {
            throw new ResourceNotFoundException("Course not found: " + courseId);
        }
        assertCanViewCourse(course);
        Set<UUID> batchIds = batchRepository.findByCourseId(courseId).stream()
                .map(Batch::getId).collect(Collectors.toSet());
        List<StudyMaterial> candidates = studyMaterialRepository.findForTargets(orNone(batchIds), Set.of(courseId));
        Access access = new Access(candidates);
        List<StudyMaterial> visible = candidates.stream()
                .filter(m -> coursesOf(m, access.batches).contains(courseId))
                .filter(access::canSee)
                .sorted(Comparator.comparing(StudyMaterial::getUploadedAt).reversed())
                .toList();
        return toResponses(visible, access);
    }

    /**
     * Every material of one type across everything this caller can see - the Song, Document and Image
     * libraries.
     *
     * <p>Built on the same scoping as the home screen rather than a query of its own, so a library can
     * never surface a file whose own screen would not show it.
     */
    @Transactional(readOnly = true)
    public List<StudyMaterialResponse> library(StudyMaterialType fileType) {
        Set<UUID> batchIds = batchSummaries().stream().map(BatchMaterialSummary::batchId).collect(Collectors.toSet());
        Set<UUID> courseIds = courseSummaries().stream().map(CourseMaterialSummary::courseId).collect(Collectors.toSet());
        if (batchIds.isEmpty() && courseIds.isEmpty()) {
            return List.of();
        }
        List<StudyMaterial> candidates = studyMaterialRepository.findForTargets(orNone(batchIds), orNone(courseIds)).stream()
                .filter(m -> fileType == null || m.getFileType() == fileType)
                .toList();
        return respondVisible(candidates);
    }

    private List<StudyMaterialResponse> respondVisible(List<StudyMaterial> candidates) {
        Access access = new Access(candidates);
        List<StudyMaterial> visible = candidates.stream()
                .filter(access::canSee)
                .sorted(Comparator.comparing(StudyMaterial::getUploadedAt).reversed())
                .toList();
        return toResponses(visible, access);
    }

    // ------------------------------------------------------------------------------------------
    // Writing
    // ------------------------------------------------------------------------------------------

    @Transactional
    @Auditable(action = "STUDY_MATERIAL_UPLOADED", entityType = "study_material")
    public StudyMaterialResponse upload(Set<UUID> batchIds, Set<UUID> courseIds, MultipartFile file, String title,
                                         String description, StudyMaterialPermission permission,
                                         StudyMaterialVisibility visibility, Set<UUID> studentIds) {
        List<MaterialTarget> targets = resolveTargets(batchIds, courseIds);
        Map<UUID, Batch> batches = batchesById(targets.stream().filter(MaterialTarget::isBatch)
                .map(MaterialTarget::getTargetId).toList());
        assertMayManage(targets, batches);

        String originalName = file.getOriginalFilename() == null
                ? "file" : file.getOriginalFilename();
        String url = fileStorageService.store(file, "study-materials", ALLOWED_CONTENT_TYPES, MAX_BYTES);
        StudyMaterialType fileType = StudyMaterialType.fromFileName(originalName);

        StudyMaterial material = studyMaterialRepository.save(StudyMaterial.builder()
                .batchId(homeBatch(targets))
                .targets(new LinkedHashSet<>(targets))
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
                .visibility(visibility != null ? visibility : StudyMaterialVisibility.ALL)
                .uploadedBy(TenantContext.currentUserId())
                .build());

        replaceAudience(material, studentIds);
        return toResponses(List.of(material), new Access(List.of(material))).get(0);
    }

    @Transactional
    @Auditable(action = "STUDY_MATERIAL_UPDATED", entityType = "study_material")
    public StudyMaterialResponse update(UUID materialId, UpdateStudyMaterialRequest request) {
        StudyMaterial material = findOrThrow(materialId);
        assertMayManage(material.getTargets(), batchesOf(List.of(material)));

        // Both null is a client that predates audiences: leave who it is for exactly as it was.
        if (request.courseIds() != null || request.batchIds() != null) {
            List<MaterialTarget> targets = resolveTargets(request.batchIds(), request.courseIds());
            Map<UUID, Batch> batches = batchesById(targets.stream().filter(MaterialTarget::isBatch)
                    .map(MaterialTarget::getTargetId).toList());
            // The new audience has to be one the caller could have created.
            assertMayManage(targets, batches);
            material.getTargets().clear();
            material.getTargets().addAll(targets);
            material.setBatchId(homeBatch(targets));
        }

        material.setTitle(request.title().trim());
        material.setDescription(
                request.description() == null || request.description().isBlank()
                        ? null : request.description().trim());
        material.setPermission(request.permission());
        material.setVisibility(
                request.visibility() != null ? request.visibility() : StudyMaterialVisibility.ALL);

        StudyMaterial saved = studyMaterialRepository.save(material);
        replaceAudience(saved, request.studentIds());
        return toResponses(List.of(saved), new Access(List.of(saved))).get(0);
    }

    @Transactional
    @Auditable(action = "STUDY_MATERIAL_DELETED", entityType = "study_material")
    public void delete(UUID materialId) {
        StudyMaterial material = findOrThrow(materialId);
        assertMayManage(material.getTargets(), batchesOf(List.of(material)));
        removeMaterial(material);
    }

    /**
     * A batch is going away: stop sharing with it. A file left with no audience at all is removed; one
     * that also reaches other batches or courses stays, just without this batch.
     */
    @Transactional
    public void detachBatch(UUID batchId) {
        MaterialTarget gone = MaterialTarget.batch(batchId);
        for (StudyMaterial material : studyMaterialRepository.findForTargets(Set.of(batchId), Set.of(NONE))) {
            material.getTargets().remove(gone);
            if (material.getTargets().isEmpty()) {
                removeMaterial(material);
            } else {
                if (batchId.equals(material.getBatchId())) {
                    material.setBatchId(homeBatch(material.getTargets()));
                }
                studyMaterialRepository.save(material);
            }
        }
    }

    private void removeMaterial(StudyMaterial material) {
        // Both cascades are manual: there are no FK constraints between these tables, so nothing
        // cleans them up on our behalf. Left behind, the audience rows would silently re-apply to
        // a future material that reused the id, and the playlist entries would render as blanks.
        studyMaterialStudentRepository.deleteByMaterialId(material.getId());
        playlistEntryRepository.deleteByMaterialId(material.getId());

        // The stored file is deliberately left on disk. Another material row could reference the
        // same upload, and an orphaned blob is a cheaper problem than a broken link on a file
        // someone else is still sharing.
        studyMaterialRepository.delete(material);
    }

    private void assertMayManage(Collection<MaterialTarget> targets, Map<UUID, Batch> batches) {
        String problem = manageProblem(targets, batches);
        if (problem != null) {
            throw new ForbiddenException(problem);
        }
    }

    /**
     * Turns the requested batch and course ids into an audience, refusing an empty one and any id that is
     * not in the caller's academy.
     */
    private List<MaterialTarget> resolveTargets(Set<UUID> batchIds, Set<UUID> courseIds) {
        Set<UUID> batches = batchIds == null ? Set.of() : batchIds;
        Set<UUID> courses = courseIds == null ? Set.of() : courseIds;
        if (batches.isEmpty() && courses.isEmpty()) {
            throw new BadRequestException("Pick at least one course or batch to share this with.");
        }
        UUID academyId = TenantContext.currentAcademyId();

        Map<UUID, Batch> foundBatches = batchesById(batches);
        Set<UUID> courseIdsToCheck = new HashSet<>(courses);
        for (UUID id : batches) {
            Batch batch = foundBatches.get(id);
            if (batch == null) {
                throw new ResourceNotFoundException("Batch not found: " + id);
            }
            courseIdsToCheck.addAll(batch.allCourseIds());
        }
        Map<UUID, Course> foundCourses = courseRepository.findAllById(courseIdsToCheck).stream()
                .collect(Collectors.toMap(Course::getId, c -> c));
        for (UUID id : courseIdsToCheck) {
            Course course = foundCourses.get(id);
            if (course == null || !academyId.equals(course.getAcademyId())) {
                throw new ResourceNotFoundException("Course not found: " + id);
            }
        }

        List<MaterialTarget> targets = new ArrayList<>();
        courses.forEach(id -> targets.add(MaterialTarget.course(id)));
        batches.forEach(id -> targets.add(MaterialTarget.batch(id)));
        return targets;
    }

    /** The first batch of an audience, or null when it is only courses. */
    private static UUID homeBatch(Collection<MaterialTarget> targets) {
        return targets.stream().filter(MaterialTarget::isBatch).map(MaterialTarget::getTargetId).findFirst().orElse(null);
    }

    /**
     * Rewrites which students a SELECTED material is shared with.
     *
     * <p>An ALL material has its rows cleared rather than kept, so switching a material back to
     * SELECTED later starts from an empty audience instead of silently restoring one chosen weeks
     * ago that nobody can now see.
     */
    private void replaceAudience(StudyMaterial material, Set<UUID> studentIds) {
        studyMaterialStudentRepository.deleteByMaterialId(material.getId());
        if (material.getVisibility() != StudyMaterialVisibility.SELECTED || studentIds == null) {
            return;
        }
        // A student outside the audience cannot be given access by naming them: visibility only ever
        // narrows within who the material already reaches.
        Set<UUID> audience = audienceOf(material.getTargets());
        studentIds.stream()
                .filter(audience::contains)
                .forEach(id -> studyMaterialStudentRepository.save(StudyMaterialStudent.builder()
                        .materialId(material.getId())
                        .membershipId(id)
                        .build()));
    }

    /** Everyone an audience reaches: the members of its batches and the people enrolled in its courses. */
    private Set<UUID> audienceOf(Collection<MaterialTarget> targets) {
        Set<UUID> people = new HashSet<>();
        for (MaterialTarget t : targets) {
            if (t.isBatch()) {
                batchMemberRepository.findByBatchId(t.getTargetId()).forEach(m -> people.add(m.getMembershipId()));
            } else {
                courseMapRepository.findByCourseId(t.getTargetId()).stream()
                        .filter(CourseMap::isActive).forEach(cm -> people.add(cm.getMembershipId()));
            }
        }
        return people;
    }

    // ------------------------------------------------------------------------------------------
    // Reading by id (playlists, the player)
    // ------------------------------------------------------------------------------------------

    /**
     * Resolves materials by id for the playlist screens, dropping any the caller cannot see.
     *
     * <p>Filtering rather than throwing: a playlist can outlive a change in who its owner
     * teaches, and one now-invisible track should not make the whole playlist unopenable.
     */
    @Transactional(readOnly = true)
    public List<StudyMaterialResponse> byIds(List<UUID> materialIds) {
        if (materialIds == null || materialIds.isEmpty()) {
            return List.of();
        }
        List<StudyMaterial> found = studyMaterialRepository.findAllById(materialIds);
        Access access = new Access(found);
        return toResponses(found.stream().filter(access::canSee).toList(), access);
    }

    /** Throws unless the caller may see this material - the guard for adding it to a playlist. */
    @Transactional(readOnly = true)
    public void assertReadable(UUID materialId) {
        StudyMaterial material = findOrThrow(materialId);
        if (!new Access(List.of(material)).canSee(material)) {
            throw new ForbiddenException("That material was not shared with you");
        }
    }

    /**
     * The batches a reader can open material for: the ones they are enrolled in, plus the ones they
     * teach.
     *
     * <p>The list counterpart of the last two branches of {@link #assertCanViewBatch} - the same two
     * routes in, so the home screen cannot offer a batch that opening would then 403 on, nor hide
     * one that opening would allow.
     */
    private List<Batch> readableBatches() {
        Caller me = caller();
        Set<UUID> batchIds = new HashSet<>(me.memberBatches());
        batchIds.addAll(me.teachingBatches());
        return batchIds.isEmpty() ? List.of() : batchRepository.findAllById(batchIds);
    }

    /**
     * Viewing a batch's files needs the edit grant on one of its courses (within the batches they were
     * given), or membership of the batch, or teaching it.
     *
     * <p>Staff are asked first on purpose is NOT the reason here - a student holds no course grants at
     * all, so the question simply falls through to membership for them.
     */
    private void assertCanViewBatch(Batch batch) {
        if (courseFeatureGuard.batchAccessible(batch.allCourseIds(), batch.getId(), FeatureKey.SYLLABUS_EDIT)) {
            return;
        }
        Caller me = caller();
        if (me.memberBatches().contains(batch.getId()) || me.teachingBatches().contains(batch.getId())) {
            return;
        }
        throw new ForbiddenException("This material belongs to a batch you're not part of");
    }

    private void assertCanViewCourse(Course course) {
        UUID courseId = course.getId();
        if (courseFeatureGuard.hasCourseFeature(courseId, FeatureKey.SYLLABUS_EDIT)
                && courseFeatureGuard.batchScope(courseId).isEmpty()) {
            return;
        }
        Caller me = caller();
        if (me.enrolledCourses().contains(courseId)) {
            return;
        }
        // A trainer who teaches one of the course's batches can read what reaches it.
        boolean teachesInCourse = batchRepository.findByCourseId(courseId).stream()
                .anyMatch(b -> me.teachingBatches().contains(b.getId()));
        if (!teachesInCourse) {
            throw new ForbiddenException("This material belongs to a course you're not part of");
        }
    }

    // ------------------------------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------------------------------

    private StudyMaterial findOrThrow(UUID id) {
        return studyMaterialRepository.findById(id)
                .orElseThrow(() -> new ResourceNotFoundException("Material not found: " + id));
    }

    private static Collection<UUID> orNone(Collection<UUID> ids) {
        return ids.isEmpty() ? Set.of(NONE) : ids;
    }

    /** "chord-chart-week1.pdf" -> "chord chart week1", so an upload without a typed title still
     * reads as something rather than showing a filename with a extension. */
    private String titleFromFileName(String fileName) {
        String withoutExtension = fileName.replaceAll("\\.[^.]+$", "");
        String spaced = withoutExtension.replaceAll("[-_]+", " ").replaceAll("\\s+", " ").trim();
        return spaced.isEmpty() ? fileName : spaced;
    }

    private List<StudyMaterialResponse> toResponses(List<StudyMaterial> materials, Access access) {
        if (materials.isEmpty()) {
            return List.of();
        }
        Map<UUID, String> namesByUser = userRepository
                .findAllById(materials.stream().map(StudyMaterial::getUploadedBy)
                        .collect(Collectors.toSet()))
                .stream().collect(Collectors.toMap(User::getId, User::getFullName));

        // One query for the whole page rather than one per material.
        Map<UUID, Set<UUID>> audience = studyMaterialStudentRepository
                .findByMaterialIdIn(materials.stream().map(StudyMaterial::getId).toList())
                .stream()
                .collect(Collectors.groupingBy(StudyMaterialStudent::getMaterialId,
                        Collectors.mapping(StudyMaterialStudent::getMembershipId, Collectors.toSet())));

        Set<UUID> courseIds = materials.stream().flatMap(m -> m.getTargets().stream())
                .filter(MaterialTarget::isCourse).map(MaterialTarget::getTargetId).collect(Collectors.toSet());
        Map<UUID, String> courseNames = courseIds.isEmpty() ? Map.of()
                : courseRepository.findAllById(courseIds).stream()
                        .collect(Collectors.toMap(Course::getId, Course::getName, (a, b) -> a));

        return materials.stream()
                .map(m -> new StudyMaterialResponse(
                        m.getId(), m.getBatchId(), m.getTitle(), m.getDescription(),
                        m.getUrl(), m.getFileName(), m.getContentType(), m.getFileType(),
                        m.getSizeBytes(), m.getPermission(),
                        m.getVisibility(), audience.getOrDefault(m.getId(), Set.of()),
                        m.getUploadedBy(),
                        namesByUser.get(m.getUploadedBy()), m.getUploadedAt(),
                        targetsOf(m, access.batches, courseNames),
                        access.canManage(m)))
                .collect(Collectors.toList());
    }

    private static List<StudyMaterialResponse.Target> targetsOf(StudyMaterial m, Map<UUID, Batch> batches,
                                                                  Map<UUID, String> courseNames) {
        List<StudyMaterialResponse.Target> out = new ArrayList<>();
        for (MaterialTarget t : m.getTargets()) {
            if (t.isCourse()) {
                out.add(new StudyMaterialResponse.Target(StudyMaterialTargetType.COURSE, t.getTargetId(),
                        courseNames.getOrDefault(t.getTargetId(), "Course")));
            }
        }
        for (MaterialTarget t : m.getTargets()) {
            if (t.isBatch()) {
                Batch b = batches.get(t.getTargetId());
                out.add(new StudyMaterialResponse.Target(StudyMaterialTargetType.BATCH, t.getTargetId(),
                        b == null ? "Batch" : b.getName()));
            }
        }
        return out;
    }
}
