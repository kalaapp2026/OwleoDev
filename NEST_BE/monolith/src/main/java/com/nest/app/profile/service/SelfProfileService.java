package com.nest.app.profile.service;

import com.nest.app.curriculum.entity.Course;
import com.nest.app.curriculum.repository.CourseRepository;
import com.nest.app.enrolment.entity.Batch;
import com.nest.app.enrolment.entity.BatchMember;
import com.nest.app.enrolment.entity.BatchTrainer;
import com.nest.app.enrolment.repository.BatchMemberRepository;
import com.nest.app.enrolment.repository.BatchRepository;
import com.nest.app.enrolment.repository.BatchTrainerRepository;
import com.nest.app.identity.entity.AcademyMembership;
import com.nest.app.identity.entity.CourseMap;
import com.nest.app.identity.entity.MembershipStatus;
import com.nest.app.identity.entity.User;
import com.nest.app.identity.repository.AcademyMembershipRepository;
import com.nest.app.identity.repository.CourseMapRepository;
import com.nest.app.identity.repository.UserRepository;
import com.nest.app.profile.dto.AchievementRequest;
import com.nest.app.profile.dto.AchievementResponse;
import com.nest.app.profile.dto.PerformanceLogRequest;
import com.nest.app.profile.dto.PerformanceLogResponse;
import com.nest.app.profile.dto.SelfProfileResponse;
import com.nest.app.profile.dto.UpdateSelfProfileRequest;
import com.nest.app.profile.entity.UserAchievement;
import com.nest.app.profile.entity.UserPerformanceLog;
import com.nest.app.profile.repository.UserAchievementRepository;
import com.nest.app.profile.repository.UserPerformanceLogRepository;
import com.nest.app.profile.dto.StudentProfileResponse;
import com.nest.common.exception.BadRequestException;
import com.nest.common.exception.ForbiddenException;
import com.nest.common.security.Role;
import com.nest.common.security.TenantContext;
import com.nest.common.exception.ResourceNotFoundException;
import com.nest.app.storage.FileStorageService;
import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;
import org.springframework.transaction.annotation.Transactional;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.TreeSet;
import java.util.UUID;
import java.util.stream.Collectors;

/**
 * The signed-in person's own profile, achievements and performance log.
 *
 * <p>Everything here is keyed by the caller's user id, taken from the token by the controller -
 * never from a path or body - so there is no id a caller could vary to reach someone else's data.
 */
@Service
public class SelfProfileService {

    static final Set<String> ACHIEVEMENT_TYPES = Set.of("AWARD", "STREAK", "CERTIFICATE", "MILESTONE");
    static final Set<String> LOG_CATEGORIES = Set.of("EXAM", "RECITAL", "ASSESSMENT", "FEEDBACK");

    private final UserRepository userRepository;
    private final AcademyMembershipRepository membershipRepository;
    private final CourseMapRepository courseMapRepository;
    private final CourseRepository courseRepository;
    private final BatchMemberRepository batchMemberRepository;
    private final BatchRepository batchRepository;
    private final BatchTrainerRepository batchTrainerRepository;
    private final UserAchievementRepository achievementRepository;
    private final UserPerformanceLogRepository performanceLogRepository;
    private final FileStorageService fileStorageService;

    public SelfProfileService(UserRepository userRepository, AcademyMembershipRepository membershipRepository,
                              CourseMapRepository courseMapRepository, CourseRepository courseRepository,
                              BatchMemberRepository batchMemberRepository, BatchRepository batchRepository,
                              BatchTrainerRepository batchTrainerRepository,
                              UserAchievementRepository achievementRepository,
                              UserPerformanceLogRepository performanceLogRepository,
                              FileStorageService fileStorageService) {
        this.fileStorageService = fileStorageService;
        this.userRepository = userRepository;
        this.membershipRepository = membershipRepository;
        this.courseMapRepository = courseMapRepository;
        this.courseRepository = courseRepository;
        this.batchMemberRepository = batchMemberRepository;
        this.batchRepository = batchRepository;
        this.batchTrainerRepository = batchTrainerRepository;
        this.achievementRepository = achievementRepository;
        this.performanceLogRepository = performanceLogRepository;
    }

    @Transactional(readOnly = true)
    public SelfProfileResponse get(UUID userId) {
        return assemble(load(userId));
    }

    @Transactional
    public SelfProfileResponse update(UUID userId, UpdateSelfProfileRequest r) {
        User user = load(userId);
        user.setFullName(r.fullName().trim());
        // Same split the registration form uses, so a later edit by an admin re-fills sensibly.
        String[] parts = user.getFullName().split("\\s+", 2);
        user.setFirstName(parts[0]);
        user.setLastName(parts.length > 1 ? parts[1] : null);
        user.setAltPhone(blankToNull(r.altPhone()));
        user.setDob(r.dob());
        user.setGender(blankToNull(r.gender()));
        user.setBloodGroup(blankToNull(r.bloodGroup()));
        user.setGuardianName(blankToNull(r.guardianName()));
        user.setAddress(blankToNull(r.addressLine1()));
        user.setAddressLine2(blankToNull(r.addressLine2()));
        user.setLandmark(blankToNull(r.landmark()));
        user.setCity(blankToNull(r.city()));
        user.setDistrict(blankToNull(r.district()));
        user.setState(blankToNull(r.state()));
        user.setPinCode(blankToNull(r.pinCode()));
        userRepository.save(user);
        return assemble(user);
    }

    @Transactional
    public SelfProfileResponse updatePhoto(UUID userId, MultipartFile file) {
        User user = load(userId);
        user.setProfileImageUrl(fileStorageService.store(file, "profile-images",
                Set.of("image/jpeg", "image/png", "image/webp"), 5L * 1024 * 1024));
        userRepository.save(user);
        return assemble(user);
    }

    /**
     * A student's profile as an Admin or Trainer sees it from More > Students: the same shape as
     * the student's own, but enrolment is limited to THIS academy (what they do elsewhere is not
     * this academy's business), and the performance log likewise. Same visibility as the existing
     * student card - any staff member of the active academy.
     */
    @Transactional(readOnly = true)
    public StudentProfileResponse forStudent(UUID membershipId) {
        AcademyMembership target = membershipRepository.findById(membershipId)
                .orElseThrow(() -> new ResourceNotFoundException("Student not found: " + membershipId));
        UUID academyId = TenantContext.currentAcademyId();
        if (!target.getAcademyId().equals(academyId) || target.getRoleType() != Role.STUDENT) {
            throw new ForbiddenException("That student does not belong to the active academy");
        }
        User user = load(target.getUserId());
        List<PerformanceLogResponse> logs = performanceLogRepository.findByUserIdOrderByLoggedOnDesc(user.getId())
                .stream()
                .filter(l -> l.getAcademyId() == null || l.getAcademyId().equals(academyId))
                .map(SelfProfileService::toResponse).toList();
        return new StudentProfileResponse(assemble(user, academyId), achievements(user.getId()), logs);
    }

    private SelfProfileResponse assemble(User u) {
        return assemble(u, null);
    }

    private SelfProfileResponse assemble(User u, UUID onlyAcademyId) {
        List<AcademyMembership> memberships = membershipRepository
                .findByUserIdAndStatus(u.getId(), MembershipStatus.ACTIVE).stream()
                .filter(m -> onlyAcademyId == null || m.getAcademyId().equals(onlyAcademyId))
                .sorted(Comparator.comparing(m -> m.getAcademyName() == null ? "" : m.getAcademyName()))
                .toList();

        // Batched lookups: one query per kind, not one per membership or course.
        Set<UUID> membershipIds = memberships.stream().map(AcademyMembership::getId).collect(Collectors.toSet());
        Map<UUID, List<CourseMap>> enrolmentsByMembership = new HashMap<>();
        Map<UUID, List<BatchMember>> batchesByMembership = new HashMap<>();
        for (UUID id : membershipIds) {
            enrolmentsByMembership.put(id, courseMapRepository.findByMembershipId(id).stream()
                    .filter(CourseMap::isActive).toList());
            batchesByMembership.put(id, batchMemberRepository.findByMembershipId(id));
        }

        Set<UUID> courseIds = enrolmentsByMembership.values().stream().flatMap(List::stream)
                .map(CourseMap::getCourseId).collect(Collectors.toSet());
        Map<UUID, Course> coursesById = courseRepository.findAllById(courseIds).stream()
                .collect(Collectors.toMap(Course::getId, c -> c));

        Set<UUID> batchIds = batchesByMembership.values().stream().flatMap(List::stream)
                .map(BatchMember::getBatchId).collect(Collectors.toSet());
        Map<UUID, Batch> batchesById = batchRepository.findAllById(batchIds).stream()
                .collect(Collectors.toMap(Batch::getId, b -> b));
        Map<UUID, List<BatchTrainer>> trainersByBatch = batchTrainerRepository.findByBatchIdIn(batchIds).stream()
                .collect(Collectors.groupingBy(BatchTrainer::getBatchId));

        Set<UUID> trainerMembershipIds = new HashSet<>();
        trainersByBatch.values().forEach(l -> l.forEach(t -> trainerMembershipIds.add(t.getTrainerMembershipId())));
        batchesById.values().forEach(b -> {
            if (b.getTrainerMembershipId() != null) trainerMembershipIds.add(b.getTrainerMembershipId());
        });
        Map<UUID, UUID> userByTrainerMembership = membershipRepository.findAllById(trainerMembershipIds).stream()
                .collect(Collectors.toMap(AcademyMembership::getId, AcademyMembership::getUserId));
        Map<UUID, String> nameByUser = userRepository.findAllById(new HashSet<>(userByTrainerMembership.values()))
                .stream().collect(Collectors.toMap(User::getId, User::getFullName));

        List<SelfProfileResponse.AcademyEnrolment> academies = new ArrayList<>();
        for (AcademyMembership m : memberships) {
            // Trainers per course come from the batches this person sits in for that course.
            Map<UUID, Set<String>> trainerNamesByCourse = new HashMap<>();
            for (BatchMember bm : batchesByMembership.get(m.getId())) {
                Batch batch = batchesById.get(bm.getBatchId());
                if (batch == null) continue;
                Set<UUID> trainerMemberships = new HashSet<>();
                if (batch.getTrainerMembershipId() != null) trainerMemberships.add(batch.getTrainerMembershipId());
                trainersByBatch.getOrDefault(batch.getId(), List.of())
                        .forEach(t -> trainerMemberships.add(t.getTrainerMembershipId()));
                Set<String> names = trainerNamesByCourse.computeIfAbsent(batch.getCourseId(), k -> new TreeSet<>());
                for (UUID tm : trainerMemberships) {
                    String name = nameByUser.get(userByTrainerMembership.get(tm));
                    if (name != null) names.add(name);
                }
            }
            List<SelfProfileResponse.Course> courses = enrolmentsByMembership.get(m.getId()).stream()
                    .map(cm -> {
                        Course c = coursesById.get(cm.getCourseId());
                        return new SelfProfileResponse.Course(cm.getCourseId(),
                                c == null ? "Unknown course" : c.getName(),
                                List.copyOf(trainerNamesByCourse.getOrDefault(cm.getCourseId(), Set.of())));
                    })
                    .sorted(Comparator.comparing(SelfProfileResponse.Course::courseName))
                    .toList();
            academies.add(new SelfProfileResponse.AcademyEnrolment(m.getAcademyId(), m.getAcademyName(),
                    m.getJoiningDate(), courses));
        }

        return new SelfProfileResponse(u.getId(), u.getUsername(), u.getFullName(), u.getEmail(), u.getPhone(),
                u.getAltPhone(), u.getDob(), u.getGender(), u.getBloodGroup(), u.getGuardianName(),
                u.getAddress(), u.getAddressLine2(), u.getLandmark(), u.getCity(), u.getDistrict(), u.getState(),
                u.getPinCode(), u.getProfileImageUrl(), u.getCreatedAt(), academies);
    }

    // ---- Achievements ----

    @Transactional(readOnly = true)
    public List<AchievementResponse> achievements(UUID userId) {
        return achievementRepository.findByUserIdOrderByAchievedOnDesc(userId).stream()
                .map(SelfProfileService::toResponse).toList();
    }

    @Transactional
    public AchievementResponse addAchievement(UUID userId, AchievementRequest r) {
        UserAchievement a = UserAchievement.builder().userId(userId).build();
        apply(a, r);
        return toResponse(achievementRepository.save(a));
    }

    @Transactional
    public AchievementResponse updateAchievement(UUID userId, UUID id, AchievementRequest r) {
        UserAchievement a = achievementRepository.findByIdAndUserId(id, userId)
                .orElseThrow(() -> new ResourceNotFoundException("Achievement not found"));
        apply(a, r);
        return toResponse(achievementRepository.save(a));
    }

    @Transactional
    public void deleteAchievement(UUID userId, UUID id) {
        achievementRepository.delete(achievementRepository.findByIdAndUserId(id, userId)
                .orElseThrow(() -> new ResourceNotFoundException("Achievement not found")));
    }

    private void apply(UserAchievement a, AchievementRequest r) {
        a.setTitle(r.title().trim());
        a.setDescription(blankToNull(r.description()));
        a.setType(requireOneOf(r.type(), ACHIEVEMENT_TYPES, "achievement type"));
        a.setAchievedOn(r.date());
        a.setAcademyId(r.academyId());
    }

    private static AchievementResponse toResponse(UserAchievement a) {
        return new AchievementResponse(a.getId(), a.getTitle(), a.getDescription(), a.getType(),
                a.getAchievedOn(), a.getAcademyId());
    }

    // ---- Performance log ----

    @Transactional(readOnly = true)
    public List<PerformanceLogResponse> performanceLogs(UUID userId) {
        return performanceLogRepository.findByUserIdOrderByLoggedOnDesc(userId).stream()
                .map(SelfProfileService::toResponse).toList();
    }

    @Transactional
    public PerformanceLogResponse addPerformanceLog(UUID userId, PerformanceLogRequest r) {
        UserPerformanceLog l = UserPerformanceLog.builder().userId(userId).build();
        apply(l, r);
        return toResponse(performanceLogRepository.save(l));
    }

    @Transactional
    public PerformanceLogResponse updatePerformanceLog(UUID userId, UUID id, PerformanceLogRequest r) {
        UserPerformanceLog l = performanceLogRepository.findByIdAndUserId(id, userId)
                .orElseThrow(() -> new ResourceNotFoundException("Performance log not found"));
        apply(l, r);
        return toResponse(performanceLogRepository.save(l));
    }

    @Transactional
    public void deletePerformanceLog(UUID userId, UUID id) {
        performanceLogRepository.delete(performanceLogRepository.findByIdAndUserId(id, userId)
                .orElseThrow(() -> new ResourceNotFoundException("Performance log not found")));
    }

    private void apply(UserPerformanceLog l, PerformanceLogRequest r) {
        l.setTitle(r.title().trim());
        l.setCategory(requireOneOf(r.category(), LOG_CATEGORIES, "performance log category"));
        l.setResult(r.result().trim());
        l.setNotes(blankToNull(r.notes()));
        l.setLoggedOn(r.date());
        l.setAcademyId(r.academyId());
    }

    private static PerformanceLogResponse toResponse(UserPerformanceLog l) {
        return new PerformanceLogResponse(l.getId(), l.getTitle(), l.getCategory(), l.getResult(),
                l.getLoggedOn(), l.getAcademyId(), l.getNotes());
    }

    // ---- helpers ----

    private User load(UUID userId) {
        return userRepository.findById(userId).orElseThrow(() -> new ResourceNotFoundException("User not found"));
    }

    private static String requireOneOf(String value, Set<String> allowed, String what) {
        String v = value == null ? "" : value.trim().toUpperCase();
        if (!allowed.contains(v)) {
            throw new BadRequestException("Unknown " + what + ": " + value);
        }
        return v;
    }

    private static String blankToNull(String s) {
        return s == null || s.isBlank() ? null : s.trim();
    }
}
