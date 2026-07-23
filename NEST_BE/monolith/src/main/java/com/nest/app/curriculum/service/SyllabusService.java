package com.nest.app.curriculum.service;

import com.nest.app.curriculum.dto.MaterialAttachmentResponse;
import com.nest.app.curriculum.dto.SyllabusUnitRequest;
import com.nest.app.curriculum.dto.SyllabusUnitResponse;
import com.nest.app.curriculum.dto.TrackResponse;
import com.nest.app.curriculum.dto.UpdateSyllabusUnitRequest;
import com.nest.app.curriculum.entity.MaterialAttachment;
import com.nest.app.curriculum.entity.ReferenceMaterialType;
import com.nest.app.curriculum.entity.SyllabusUnit;
import com.nest.app.curriculum.entity.SyllabusUnitStatus;
import com.nest.app.curriculum.entity.Track;
import com.nest.app.curriculum.repository.MaterialAttachmentRepository;
import com.nest.app.curriculum.repository.SyllabusUnitRepository;
import com.nest.app.curriculum.repository.TrackRepository;
import com.nest.app.enrolment.repository.BatchMemberRepository;
import com.nest.app.enrolment.repository.BatchRepository;
import com.nest.app.identity.entity.AcademyMembership;
import com.nest.app.identity.repository.AcademyMembershipRepository;
import com.nest.app.identity.repository.CourseMapRepository;
import com.nest.app.storage.FileStorageService;
import com.nest.common.audit.Auditable;
import com.nest.common.exception.BadRequestException;
import com.nest.common.exception.ForbiddenException;
import com.nest.common.exception.ResourceNotFoundException;
import com.nest.common.security.TenantContext;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.multipart.MultipartFile;

import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;

/** PRD 3.11 - what's being taught, segmented by course/batch, plus each unit's PDF/image
 * attachments ({@link MaterialAttachment}) and song attachments ({@link Track}). */
@Service
public class SyllabusService {

    private static final Set<String> MATERIAL_CONTENT_TYPES = Set.of("image/jpeg", "image/png", "image/webp", "application/pdf");
    private static final long MATERIAL_MAX_BYTES = 15L * 1024 * 1024;
    private static final Set<String> AUDIO_CONTENT_TYPES =
            Set.of("audio/mpeg", "audio/mp4", "audio/wav", "audio/x-wav", "audio/ogg", "audio/webm", "audio/aac");
    private static final long AUDIO_MAX_BYTES = 25L * 1024 * 1024;

    private final SyllabusUnitRepository syllabusUnitRepository;
    private final TrackRepository trackRepository;
    private final MaterialAttachmentRepository materialAttachmentRepository;
    private final CourseMapRepository courseMapRepository;
    private final AcademyMembershipRepository membershipRepository;
    private final BatchRepository batchRepository;
    private final BatchMemberRepository batchMemberRepository;
    private final FileStorageService fileStorageService;

    public SyllabusService(SyllabusUnitRepository syllabusUnitRepository, TrackRepository trackRepository,
                            MaterialAttachmentRepository materialAttachmentRepository, CourseMapRepository courseMapRepository,
                            AcademyMembershipRepository membershipRepository, BatchRepository batchRepository,
                            BatchMemberRepository batchMemberRepository, FileStorageService fileStorageService) {
        this.syllabusUnitRepository = syllabusUnitRepository;
        this.trackRepository = trackRepository;
        this.materialAttachmentRepository = materialAttachmentRepository;
        this.courseMapRepository = courseMapRepository;
        this.membershipRepository = membershipRepository;
        this.batchRepository = batchRepository;
        this.batchMemberRepository = batchMemberRepository;
        this.fileStorageService = fileStorageService;
    }

    @Transactional
    @Auditable(action = "SYLLABUS_UNIT_CREATED", entityType = "syllabus_unit")
    public SyllabusUnitResponse createUnit(SyllabusUnitRequest request) {
        SyllabusUnit unit = SyllabusUnit.builder()
                .courseId(request.courseId())
                .batchIds(request.batchIds() == null ? new HashSet<>() : new HashSet<>(request.batchIds()))
                .title(request.title())
                .description(request.description())
                .orderIndex(request.orderIndex())
                .status(SyllabusUnitStatus.NOT_STARTED)
                .build();
        return toResponse(syllabusUnitRepository.save(unit));
    }

    @Transactional
    @Auditable(action = "SYLLABUS_UNIT_UPDATED", entityType = "syllabus_unit")
    public SyllabusUnitResponse updateUnit(UUID unitId, UpdateSyllabusUnitRequest request) {
        SyllabusUnit unit = findOrThrow(unitId);
        unit.setTitle(request.title());
        unit.setDescription(request.description());
        unit.setBatchIds(request.batchIds() == null ? new HashSet<>() : new HashSet<>(request.batchIds()));
        unit.setOrderIndex(request.orderIndex());
        return toResponse(syllabusUnitRepository.save(unit));
    }

    /** No FK cascade in this schema (consistent with every other delete in this codebase) - a
     * unit's tracks and material attachments are removed from the DB explicitly before the unit
     * itself goes. Their uploaded files stay on disk (a small, acceptable dev-stage leak - see
     * FileStorageService). */
    @Transactional
    @Auditable(action = "SYLLABUS_UNIT_DELETED", entityType = "syllabus_unit")
    public void deleteUnit(UUID unitId) {
        SyllabusUnit unit = findOrThrow(unitId);
        trackRepository.deleteBySyllabusUnitId(unitId);
        materialAttachmentRepository.deleteBySyllabusUnitId(unitId);
        syllabusUnitRepository.delete(unit);
    }

    /** A unit can carry several PDF/image attachments - each call adds one more rather than
     * replacing whatever was there before. */
    @Transactional
    @Auditable(action = "SYLLABUS_MATERIAL_ATTACHMENT_ADDED", entityType = "syllabus_unit")
    public MaterialAttachmentResponse addAttachment(UUID unitId, MultipartFile file) {
        findOrThrow(unitId); // 404s cleanly instead of orphaning a file upload against a missing unit
        String contentType = file.getContentType();
        String url = fileStorageService.store(file, "course-materials", MATERIAL_CONTENT_TYPES, MATERIAL_MAX_BYTES);
        MaterialAttachment attachment = MaterialAttachment.builder()
                .syllabusUnitId(unitId)
                .url(url)
                .materialType(contentType != null && contentType.equalsIgnoreCase("application/pdf")
                        ? ReferenceMaterialType.PDF : ReferenceMaterialType.IMAGE)
                .contentType(contentType)
                .build();
        return toAttachmentResponse(materialAttachmentRepository.save(attachment));
    }

    @Transactional(readOnly = true)
    public List<MaterialAttachmentResponse> listAttachments(UUID unitId) {
        return materialAttachmentRepository.findBySyllabusUnitIdOrderByUploadedAt(unitId).stream()
                .map(this::toAttachmentResponse).collect(Collectors.toList());
    }

    @Transactional
    @Auditable(action = "SYLLABUS_MATERIAL_ATTACHMENT_DELETED", entityType = "syllabus_unit")
    public void deleteAttachment(UUID unitId, UUID attachmentId) {
        MaterialAttachment attachment = materialAttachmentRepository.findById(attachmentId)
                .orElseThrow(() -> new ResourceNotFoundException("Attachment not found: " + attachmentId));
        if (!attachment.getSyllabusUnitId().equals(unitId)) {
            throw new ResourceNotFoundException("Attachment not found: " + attachmentId);
        }
        materialAttachmentRepository.delete(attachment);
    }

    /** Unscoped (membershipId == null) is the Admin/Trainer management view - everything in the
     * course regardless of targeting, so they can see and edit material they haven't personally
     * enrolled into. Scoped is what a Student (or a Trainer checking their own access) actually
     * sees: course-wide material if enrolled in the course at all, plus batch-targeted material
     * only for batches they're a member of or - for a Trainer - teach. */
    @Transactional(readOnly = true)
    public List<SyllabusUnitResponse> listForCourse(UUID courseId, UUID membershipId) {
        List<SyllabusUnit> units = syllabusUnitRepository.findByCourseIdOrderByOrderIndex(courseId);
        if (membershipId == null) {
            return units.stream().map(this::toResponse).collect(Collectors.toList());
        }

        AcademyMembership membership = membershipRepository.findById(membershipId)
                .orElseThrow(() -> new ResourceNotFoundException("Membership not found: " + membershipId));
        if (!membership.getAcademyId().equals(TenantContext.currentAcademyId())) {
            throw new ForbiddenException("That membership does not belong to the active academy");
        }

        boolean enrolledInCourse = courseMapRepository.findByMembershipIdAndCourseId(membershipId, courseId).isPresent();

        Set<UUID> accessibleBatchIds = new HashSet<>();
        batchMemberRepository.findByMembershipId(membershipId).forEach(bm -> accessibleBatchIds.add(bm.getBatchId()));
        batchRepository.findByTrainerMembershipId(membershipId).forEach(b -> accessibleBatchIds.add(b.getId()));

        return units.stream()
                .filter(u -> u.getBatchIds().isEmpty() ? enrolledInCourse : u.getBatchIds().stream().anyMatch(accessibleBatchIds::contains))
                .map(this::toResponse)
                .collect(Collectors.toList());
    }

    /** Gives a batch a simple progress bar (PRD 3.11). */
    @Transactional
    @Auditable(action = "SYLLABUS_UNIT_STATUS_CHANGED", entityType = "syllabus_unit")
    public SyllabusUnitResponse setUnitStatus(UUID unitId, SyllabusUnitStatus status) {
        SyllabusUnit unit = findOrThrow(unitId);
        unit.setStatus(status);
        return toResponse(syllabusUnitRepository.save(unit));
    }

    @Transactional
    @Auditable(action = "TRACK_ADDED", entityType = "track")
    public TrackResponse addTrack(UUID syllabusUnitId, String title, boolean streamOnly, MultipartFile file) {
        findOrThrow(syllabusUnitId); // 404s cleanly instead of orphaning a file upload against a missing unit
        if (title == null || title.isBlank()) {
            throw new BadRequestException("A song needs a title");
        }
        String url = fileStorageService.store(file, "tracks", AUDIO_CONTENT_TYPES, AUDIO_MAX_BYTES);
        Track track = Track.builder()
                .syllabusUnitId(syllabusUnitId)
                .title(title)
                .storageKey(url)
                .contentType(file.getContentType())
                .streamOnly(streamOnly)
                .build();
        return toTrackResponse(trackRepository.save(track));
    }

    @Transactional
    @Auditable(action = "TRACK_DELETED", entityType = "track")
    public void deleteTrack(UUID syllabusUnitId, UUID trackId) {
        Track track = trackRepository.findById(trackId)
                .orElseThrow(() -> new ResourceNotFoundException("Track not found: " + trackId));
        if (!track.getSyllabusUnitId().equals(syllabusUnitId)) {
            throw new ResourceNotFoundException("Track not found: " + trackId);
        }
        trackRepository.delete(track);
    }

    @Transactional(readOnly = true)
    public List<TrackResponse> listTracks(UUID syllabusUnitId) {
        return trackRepository.findBySyllabusUnitId(syllabusUnitId).stream()
                .map(this::toTrackResponse).collect(Collectors.toList());
    }

    private SyllabusUnit findOrThrow(UUID unitId) {
        return syllabusUnitRepository.findById(unitId)
                .orElseThrow(() -> new ResourceNotFoundException("Syllabus unit not found: " + unitId));
    }

    /** Set.copyOf forces the lazy @ElementCollection to actually load here, while the transaction
     * (and Hibernate session) is still open - returning u.getBatchIds() directly hands Jackson an
     * uninitialised proxy it only tries to iterate later, after the session has already closed
     * (open-in-view is off), which throws LazyInitializationException instead of serialising. */
    private SyllabusUnitResponse toResponse(SyllabusUnit u) {
        return new SyllabusUnitResponse(u.getId(), u.getCourseId(), Set.copyOf(u.getBatchIds()), u.getTitle(),
                u.getDescription(), u.getOrderIndex(), u.getStatus());
    }

    private MaterialAttachmentResponse toAttachmentResponse(MaterialAttachment a) {
        return new MaterialAttachmentResponse(a.getId(), a.getSyllabusUnitId(), a.getUrl(), a.getMaterialType(), a.getContentType());
    }

    private TrackResponse toTrackResponse(Track t) {
        return new TrackResponse(t.getId(), t.getSyllabusUnitId(), t.getTitle(), t.getStorageKey(), t.getContentType(), t.isStreamOnly());
    }
}
