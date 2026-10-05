package com.nest.app.academy.service;

import com.nest.app.academy.dto.AcademyProfileResponse;
import com.nest.app.academy.dto.AddBranchRequest;
import com.nest.app.academy.dto.AddFeaturedTrainerRequest;
import com.nest.app.academy.dto.AddHighlightRequest;
import com.nest.app.academy.dto.BranchResponse;
import com.nest.app.academy.dto.FeaturedTrainerResponse;
import com.nest.app.academy.dto.HighlightResponse;
import com.nest.app.academy.dto.HighlightTrainerResponse;
import com.nest.app.academy.dto.TrainerCandidateResponse;
import com.nest.app.academy.dto.UpdateAcademyProfileRequest;
import com.nest.app.academy.dto.UpdateFeaturedTrainerRequest;
import com.nest.app.academy.dto.UpdateHighlightRequest;
import com.nest.app.academy.entity.Academy;
import com.nest.app.academy.entity.AcademyBranch;
import com.nest.app.academy.entity.AcademyFeaturedTrainer;
import com.nest.app.academy.entity.AcademyHighlight;
import com.nest.app.academy.entity.AcademyHighlightImage;
import com.nest.app.academy.repository.AcademyBranchRepository;
import com.nest.app.academy.repository.AcademyFeaturedTrainerRepository;
import com.nest.app.academy.repository.AcademyHighlightImageRepository;
import com.nest.app.academy.repository.AcademyHighlightRepository;
import com.nest.app.academy.repository.AcademyRepository;
import com.nest.app.curriculum.entity.Course;
import com.nest.app.curriculum.repository.CourseRepository;
import com.nest.app.identity.entity.AcademyMembership;
import com.nest.app.identity.entity.CourseMap;
import com.nest.app.identity.entity.MembershipStatus;
import com.nest.app.identity.entity.User;
import com.nest.app.identity.repository.AcademyMembershipRepository;
import com.nest.app.identity.repository.CourseMapRepository;
import com.nest.app.identity.repository.UserRepository;
import com.nest.app.storage.FileStorageService;
import com.nest.common.audit.Auditable;
import com.nest.common.exception.BadRequestException;
import com.nest.common.exception.ConflictException;
import com.nest.common.exception.ResourceNotFoundException;
import com.nest.common.security.Role;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.multipart.MultipartFile;

import java.util.Comparator;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;

/** PRD 3.10 About-Us page - a singleton per academy. Read is open to any member of the academy;
 * every mutation here is gated at the controller by {@code @RequiresFeature(ABOUT_US_EDIT)},
 * which only ACADEMY_ADMIN ever holds (the feature is in {@code FeatureKey.NON_DELEGABLE}). */
@Service
public class AcademyProfileService {

    private static final Set<String> IMAGE_CONTENT_TYPES = Set.of("image/jpeg", "image/png", "image/webp");
    private static final long IMAGE_MAX_BYTES = 5L * 1024 * 1024;
    private static final Set<String> HIDEABLE_LINKS = Set.of("instagram", "x", "facebook", "youtube", "website", "maps");

    private final AcademyRepository academyRepository;
    private final AcademyHighlightRepository highlightRepository;
    private final AcademyHighlightImageRepository highlightImageRepository;
    private final AcademyFeaturedTrainerRepository featuredTrainerRepository;
    private final AcademyBranchRepository branchRepository;
    private final AcademyMembershipRepository membershipRepository;
    private final UserRepository userRepository;
    private final FileStorageService fileStorageService;
    private final CourseMapRepository courseMapRepository;
    private final CourseRepository courseRepository;

    public AcademyProfileService(AcademyRepository academyRepository, AcademyHighlightRepository highlightRepository,
                                  AcademyHighlightImageRepository highlightImageRepository,
                                  AcademyFeaturedTrainerRepository featuredTrainerRepository, AcademyBranchRepository branchRepository,
                                  AcademyMembershipRepository membershipRepository, UserRepository userRepository,
                                  FileStorageService fileStorageService, CourseMapRepository courseMapRepository,
                                  CourseRepository courseRepository) {
        this.courseMapRepository = courseMapRepository;
        this.courseRepository = courseRepository;
        this.academyRepository = academyRepository;
        this.highlightRepository = highlightRepository;
        this.highlightImageRepository = highlightImageRepository;
        this.featuredTrainerRepository = featuredTrainerRepository;
        this.branchRepository = branchRepository;
        this.membershipRepository = membershipRepository;
        this.userRepository = userRepository;
        this.fileStorageService = fileStorageService;
    }

    @Transactional(readOnly = true)
    public AcademyProfileResponse getProfile(UUID academyId) {
        Academy academy = findOrThrow(academyId);

        List<AcademyHighlight> highlightEntities = highlightRepository.findByAcademyIdOrderByOrderIndex(academyId);
        List<HighlightResponse> highlights = highlightEntities.stream()
                .map(this::toHighlightResponse)
                .collect(Collectors.toList());

        List<AcademyFeaturedTrainer> featured = featuredTrainerRepository.findByAcademyIdOrderByOrderIndex(academyId);
        List<FeaturedTrainerResponse> featuredTrainers = resolveFeaturedTrainers(featured);

        List<BranchResponse> branches = branchRepository.findByAcademyIdOrderByOrderIndex(academyId).stream()
                .map(b -> new BranchResponse(b.getId(), b.getName(), b.getAddress()))
                .collect(Collectors.toList());

        return toResponse(academy, highlights, featuredTrainers, branches);
    }

    /** Publish: the frontend's whole draft in one write. See {@link UpdateAcademyProfileRequest}
     * for which fields a null leaves untouched. */
    @Transactional
    @Auditable(action = "ACADEMY_PROFILE_UPDATED", entityType = "academy")
    public AcademyProfileResponse updateProfile(UUID academyId, UpdateAcademyProfileRequest request) {
        Academy academy = findOrThrow(academyId);
        String name = trimToNull(request.name()) != null ? request.name().trim() : academy.getName();
        String city = trimToNull(request.city()) != null ? request.city().trim() : academy.getCity();
        if ((!name.equalsIgnoreCase(academy.getName()) || !city.equalsIgnoreCase(academy.getCity()))
                && academyRepository.existsByNameIgnoreCaseAndCityIgnoreCaseAndIdNot(name, city, academyId)) {
            throw new ConflictException("Another academy called \"" + name + "\" is already registered in " + city);
        }
        academy.setName(name);
        academy.setCity(city);
        if (trimToNull(request.state()) != null) {
            academy.setState(request.state().trim());
        }
        if (request.area() != null) {
            academy.setArea(trimToNull(request.area()));
        }
        if (request.pinCode() != null) {
            academy.setPinCode(trimToNull(request.pinCode()));
        }
        if (request.coverStyle() != null) {
            academy.setCoverStyle(trimToNull(request.coverStyle()));
        }
        if (request.logoColor() != null) {
            academy.setLogoColor(trimToNull(request.logoColor()));
        }
        if (request.hiddenLinks() != null) {
            String hidden = request.hiddenLinks().stream()
                    .map(String::trim)
                    .filter(HIDEABLE_LINKS::contains)
                    .distinct()
                    .collect(Collectors.joining(","));
            academy.setHiddenLinks(hidden.isEmpty() ? null : hidden);
        }
        if (Boolean.TRUE.equals(request.removeLogo())) {
            academy.setLogoUrl(null);
        }
        if (Boolean.TRUE.equals(request.removeCover())) {
            academy.setCoverImageUrl(null);
        }
        if (request.featuredTrainers() != null) {
            replaceFeaturedTrainers(academyId, request.featuredTrainers());
        }
        academy.setTagline(blankToNull(request.tagline()));
        academy.setDescription(blankToNull(request.description()));
        academy.setEstablishedBy(blankToNull(request.establishedBy()));
        academy.setOwnerName(blankToNull(request.ownerName()));
        academy.setAdditionalInfo(blankToNull(request.additionalInfo()));
        if (request.address() != null && !request.address().isBlank()) {
            academy.setAddress(request.address());
        }
        if (request.contactNumber() != null && !request.contactNumber().isBlank()) {
            academy.setContactNumber(request.contactNumber());
        }
        academy.setEmail(blankToNull(request.email()));
        academy.setInstagramUrl(blankToNull(request.instagramUrl()));
        academy.setXUrl(blankToNull(request.xUrl()));
        academy.setFacebookUrl(blankToNull(request.facebookUrl()));
        academy.setYoutubeUrl(blankToNull(request.youtubeUrl()));
        academy.setWhatsapp(blankToNull(request.whatsapp()));
        academy.setWebsiteUrl(blankToNull(request.websiteUrl()));
        academy.setMapsUrl(blankToNull(request.mapsUrl()));
        academyRepository.save(academy);
        return getProfile(academyId);
    }

    @Transactional
    @Auditable(action = "ACADEMY_LOGO_UPLOADED", entityType = "academy")
    public AcademyProfileResponse uploadLogo(UUID academyId, MultipartFile file) {
        Academy academy = findOrThrow(academyId);
        String url = fileStorageService.store(file, "academy-logos", IMAGE_CONTENT_TYPES, IMAGE_MAX_BYTES);
        academy.setLogoUrl(url);
        academyRepository.save(academy);
        return getProfile(academyId);
    }

    @Transactional
    @Auditable(action = "ACADEMY_COVER_IMAGE_UPLOADED", entityType = "academy")
    public AcademyProfileResponse uploadCoverImage(UUID academyId, MultipartFile file) {
        Academy academy = findOrThrow(academyId);
        String url = fileStorageService.store(file, "academy-covers", IMAGE_CONTENT_TYPES, IMAGE_MAX_BYTES);
        academy.setCoverImageUrl(url);
        academyRepository.save(academy);
        return getProfile(academyId);
    }

    @Transactional
    @Auditable(action = "ACADEMY_HIGHLIGHT_ADDED", entityType = "academy")
    public HighlightResponse addHighlight(UUID academyId, AddHighlightRequest request) {
        findOrThrow(academyId);
        AcademyHighlight highlight = AcademyHighlight.builder()
                .academyId(academyId)
                .title(request.title())
                .description(request.description())
                .trainerMembershipIds(request.trainerMembershipIds() == null ? new HashSet<>() : new HashSet<>(request.trainerMembershipIds()))
                .orderIndex(highlightRepository.findByAcademyIdOrderByOrderIndex(academyId).size())
                .build();
        highlight = highlightRepository.save(highlight);
        return toHighlightResponse(highlight);
    }

    @Transactional
    @Auditable(action = "ACADEMY_HIGHLIGHT_UPDATED", entityType = "academy")
    public HighlightResponse updateHighlight(UUID academyId, UUID highlightId, UpdateHighlightRequest request) {
        AcademyHighlight highlight = findHighlightOrThrow(academyId, highlightId);
        highlight.setTitle(request.title());
        highlight.setDescription(request.description());
        highlight.setTrainerMembershipIds(request.trainerMembershipIds() == null ? new HashSet<>() : new HashSet<>(request.trainerMembershipIds()));
        highlight = highlightRepository.save(highlight);
        return toHighlightResponse(highlight);
    }

    /** A highlight can carry several photos, shown as a carousel - each call adds one more. */
    @Transactional
    @Auditable(action = "ACADEMY_HIGHLIGHT_IMAGE_ADDED", entityType = "academy")
    public HighlightResponse addHighlightImage(UUID academyId, UUID highlightId, MultipartFile file) {
        AcademyHighlight highlight = findHighlightOrThrow(academyId, highlightId);
        String url = fileStorageService.store(file, "academy-highlights", IMAGE_CONTENT_TYPES, IMAGE_MAX_BYTES);
        AcademyHighlightImage image = AcademyHighlightImage.builder()
                .highlightId(highlightId)
                .url(url)
                .orderIndex(highlightImageRepository.findByHighlightIdOrderByOrderIndex(highlightId).size())
                .build();
        highlightImageRepository.save(image);
        return toHighlightResponse(highlight);
    }

    @Transactional
    @Auditable(action = "ACADEMY_HIGHLIGHT_IMAGE_DELETED", entityType = "academy")
    public void deleteHighlightImage(UUID academyId, UUID highlightId, UUID imageId) {
        findHighlightOrThrow(academyId, highlightId);
        AcademyHighlightImage image = highlightImageRepository.findById(imageId)
                .orElseThrow(() -> new ResourceNotFoundException("Image not found: " + imageId));
        if (!image.getHighlightId().equals(highlightId)) {
            throw new ResourceNotFoundException("Image not found: " + imageId);
        }
        highlightImageRepository.delete(image);
    }

    /** No FK cascade in this schema (consistent everywhere else) - a highlight's photos are
     * removed from the DB explicitly before the highlight itself goes; its trainer links go
     * automatically since Hibernate owns that @ElementCollection table directly. */
    @Transactional
    @Auditable(action = "ACADEMY_HIGHLIGHT_DELETED", entityType = "academy")
    public void deleteHighlight(UUID academyId, UUID highlightId) {
        AcademyHighlight highlight = findHighlightOrThrow(academyId, highlightId);
        highlightImageRepository.deleteByHighlightId(highlightId);
        highlightRepository.delete(highlight);
    }

    /** The Admin's "pick a trainer to feature" source - every active Trainer, PLUS every active
     * Academy Admin (who often teaches too, even without a course mapping) - same reasoning as
     * the batch default-trainer picker. */
    @Transactional(readOnly = true)
    public List<TrainerCandidateResponse> listTrainerCandidates(UUID academyId) {
        List<AcademyMembership> trainers = membershipRepository.findByAcademyIdAndRoleTypeAndStatus(
                academyId, Role.TRAINER, MembershipStatus.ACTIVE);
        List<AcademyMembership> admins = membershipRepository.findByAcademyIdAndRoleTypeAndStatus(
                academyId, Role.ACADEMY_ADMIN, MembershipStatus.ACTIVE);

        Map<UUID, AcademyMembership> membershipsById = new LinkedHashMap<>();
        trainers.forEach(m -> membershipsById.put(m.getId(), m));
        admins.forEach(m -> membershipsById.putIfAbsent(m.getId(), m));

        Map<UUID, User> usersById = userRepository.findAllById(
                membershipsById.values().stream().map(AcademyMembership::getUserId).collect(Collectors.toSet())
        ).stream().collect(Collectors.toMap(User::getId, u -> u));

        Map<UUID, List<UUID>> courseIdsByMembership = membershipsById.keySet().stream()
                .collect(Collectors.toMap(id -> id, id -> courseMapRepository.findByMembershipId(id).stream()
                        .filter(CourseMap::isActive)
                        .map(CourseMap::getCourseId)
                        .collect(Collectors.toList())));
        Map<UUID, String> courseNames = courseRepository.findAllById(
                courseIdsByMembership.values().stream().flatMap(List::stream).collect(Collectors.toSet())
        ).stream().collect(Collectors.toMap(Course::getId, Course::getName));

        return membershipsById.values().stream()
                .map(m -> {
                    User u = usersById.get(m.getUserId());
                    List<String> names = courseIdsByMembership.get(m.getId()).stream()
                            .map(courseNames::get)
                            .filter(n -> n != null)
                            .sorted()
                            .collect(Collectors.toList());
                    return new TrainerCandidateResponse(m.getId(), u.getFullName(), u.getProfileImageUrl(), names);
                })
                .sorted(Comparator.comparing(TrainerCandidateResponse::fullName, String.CASE_INSENSITIVE_ORDER))
                .collect(Collectors.toList());
    }

    @Transactional
    @Auditable(action = "ACADEMY_FEATURED_TRAINER_ADDED", entityType = "academy")
    public FeaturedTrainerResponse addFeaturedTrainer(UUID academyId, AddFeaturedTrainerRequest request) {
        AcademyMembership membership = membershipRepository.findById(request.trainerMembershipId())
                .orElseThrow(() -> new ResourceNotFoundException("Membership not found: " + request.trainerMembershipId()));
        if (!membership.getAcademyId().equals(academyId) || (membership.getRoleType() != Role.TRAINER && membership.getRoleType() != Role.ACADEMY_ADMIN)) {
            throw new BadRequestException("That membership is not an active Trainer/Admin at this academy");
        }
        AcademyFeaturedTrainer featured = AcademyFeaturedTrainer.builder()
                .academyId(academyId)
                .trainerMembershipId(request.trainerMembershipId())
                .designation(blankToNull(request.designation()))
                .orderIndex(featuredTrainerRepository.findByAcademyIdOrderByOrderIndex(academyId).size())
                .build();
        featured = featuredTrainerRepository.save(featured);
        return resolveFeaturedTrainers(List.of(featured)).get(0);
    }

    /** Swaps the whole featured list for [entries], in order - how Publish saves the draft's list.
     * Every entry is validated before anything is deleted, so a bad id leaves the old list intact. */
    private void replaceFeaturedTrainers(UUID academyId, List<UpdateAcademyProfileRequest.FeaturedTrainerEntry> entries) {
        Set<UUID> seen = new HashSet<>();
        List<UpdateAcademyProfileRequest.FeaturedTrainerEntry> unique = entries.stream()
                .filter(e -> seen.add(e.trainerMembershipId()))
                .collect(Collectors.toList());
        Map<UUID, AcademyMembership> memberships = membershipRepository.findAllById(seen).stream()
                .collect(Collectors.toMap(AcademyMembership::getId, m -> m));
        for (var entry : unique) {
            AcademyMembership m = memberships.get(entry.trainerMembershipId());
            if (m == null || !m.getAcademyId().equals(academyId)
                    || (m.getRoleType() != Role.TRAINER && m.getRoleType() != Role.ACADEMY_ADMIN)) {
                throw new BadRequestException("That membership is not an active Trainer/Admin at this academy");
            }
        }
        featuredTrainerRepository.deleteAll(featuredTrainerRepository.findByAcademyIdOrderByOrderIndex(academyId));
        featuredTrainerRepository.flush();
        for (int i = 0; i < unique.size(); i++) {
            var entry = unique.get(i);
            featuredTrainerRepository.save(AcademyFeaturedTrainer.builder()
                    .academyId(academyId)
                    .trainerMembershipId(entry.trainerMembershipId())
                    .designation(trimToNull(entry.designation()))
                    .orderIndex(i)
                    .build());
        }
    }

    @Transactional
    @Auditable(action = "ACADEMY_FEATURED_TRAINER_UPDATED", entityType = "academy")
    public FeaturedTrainerResponse updateFeaturedTrainer(UUID academyId, UUID featuredTrainerId, UpdateFeaturedTrainerRequest request) {
        AcademyFeaturedTrainer featured = featuredTrainerRepository.findById(featuredTrainerId)
                .orElseThrow(() -> new ResourceNotFoundException("Featured trainer not found: " + featuredTrainerId));
        if (!featured.getAcademyId().equals(academyId)) {
            throw new ResourceNotFoundException("Featured trainer not found: " + featuredTrainerId);
        }
        featured.setDesignation(blankToNull(request.designation()));
        featured = featuredTrainerRepository.save(featured);
        return resolveFeaturedTrainers(List.of(featured)).get(0);
    }

    @Transactional
    @Auditable(action = "ACADEMY_FEATURED_TRAINER_REMOVED", entityType = "academy")
    public void deleteFeaturedTrainer(UUID academyId, UUID featuredTrainerId) {
        AcademyFeaturedTrainer featured = featuredTrainerRepository.findById(featuredTrainerId)
                .orElseThrow(() -> new ResourceNotFoundException("Featured trainer not found: " + featuredTrainerId));
        if (!featured.getAcademyId().equals(academyId)) {
            throw new ResourceNotFoundException("Featured trainer not found: " + featuredTrainerId);
        }
        featuredTrainerRepository.delete(featured);
    }

    @Transactional
    @Auditable(action = "ACADEMY_BRANCH_ADDED", entityType = "academy")
    public BranchResponse addBranch(UUID academyId, AddBranchRequest request) {
        findOrThrow(academyId);
        AcademyBranch branch = AcademyBranch.builder()
                .academyId(academyId)
                .name(request.name())
                .address(request.address())
                .orderIndex(branchRepository.findByAcademyIdOrderByOrderIndex(academyId).size())
                .build();
        branch = branchRepository.save(branch);
        return new BranchResponse(branch.getId(), branch.getName(), branch.getAddress());
    }

    @Transactional
    @Auditable(action = "ACADEMY_BRANCH_DELETED", entityType = "academy")
    public void deleteBranch(UUID academyId, UUID branchId) {
        AcademyBranch branch = branchRepository.findById(branchId)
                .orElseThrow(() -> new ResourceNotFoundException("Branch not found: " + branchId));
        if (!branch.getAcademyId().equals(academyId)) {
            throw new ResourceNotFoundException("Branch not found: " + branchId);
        }
        branchRepository.delete(branch);
    }

    private HighlightResponse toHighlightResponse(AcademyHighlight highlight) {
        List<String> imageUrls = highlightImageRepository.findByHighlightIdOrderByOrderIndex(highlight.getId()).stream()
                .map(AcademyHighlightImage::getUrl)
                .collect(Collectors.toList());
        // Set.copyOf-equivalent read here, same reasoning as SyllabusUnit.batchIds - forces the
        // lazy @ElementCollection to load while the transaction is still open.
        List<HighlightTrainerResponse> trainers = resolveHighlightTrainers(Set.copyOf(highlight.getTrainerMembershipIds()));
        return new HighlightResponse(highlight.getId(), highlight.getTitle(), highlight.getDescription(), imageUrls, trainers);
    }

    private List<HighlightTrainerResponse> resolveHighlightTrainers(Set<UUID> trainerMembershipIds) {
        if (trainerMembershipIds.isEmpty()) {
            return List.of();
        }
        Map<UUID, AcademyMembership> membershipsById = membershipRepository.findAllById(trainerMembershipIds).stream()
                .collect(Collectors.toMap(AcademyMembership::getId, m -> m));
        Map<UUID, User> usersById = userRepository.findAllById(
                membershipsById.values().stream().map(AcademyMembership::getUserId).collect(Collectors.toSet())
        ).stream().collect(Collectors.toMap(User::getId, u -> u));

        return trainerMembershipIds.stream()
                .map(id -> {
                    AcademyMembership m = membershipsById.get(id);
                    User u = m == null ? null : usersById.get(m.getUserId());
                    return new HighlightTrainerResponse(id, u == null ? "Unknown" : u.getFullName(), u == null ? null : u.getProfileImageUrl());
                })
                .collect(Collectors.toList());
    }

    private List<FeaturedTrainerResponse> resolveFeaturedTrainers(List<AcademyFeaturedTrainer> featured) {
        if (featured.isEmpty()) {
            return List.of();
        }
        Map<UUID, AcademyMembership> membershipsById = membershipRepository.findAllById(
                featured.stream().map(AcademyFeaturedTrainer::getTrainerMembershipId).collect(Collectors.toSet())
        ).stream().collect(Collectors.toMap(AcademyMembership::getId, m -> m));
        Map<UUID, User> usersById = userRepository.findAllById(
                membershipsById.values().stream().map(AcademyMembership::getUserId).collect(Collectors.toSet())
        ).stream().collect(Collectors.toMap(User::getId, u -> u));

        return featured.stream()
                .map(f -> {
                    AcademyMembership m = membershipsById.get(f.getTrainerMembershipId());
                    User u = m == null ? null : usersById.get(m.getUserId());
                    return new FeaturedTrainerResponse(f.getId(), f.getTrainerMembershipId(),
                            u == null ? "Unknown" : u.getFullName(), u == null ? null : u.getProfileImageUrl(),
                            f.getDesignation());
                })
                .collect(Collectors.toList());
    }

    private Academy findOrThrow(UUID academyId) {
        return academyRepository.findById(academyId)
                .orElseThrow(() -> new ResourceNotFoundException("Academy not found: " + academyId));
    }

    private AcademyHighlight findHighlightOrThrow(UUID academyId, UUID highlightId) {
        AcademyHighlight highlight = highlightRepository.findById(highlightId)
                .orElseThrow(() -> new ResourceNotFoundException("Highlight not found: " + highlightId));
        if (!highlight.getAcademyId().equals(academyId)) {
            throw new ResourceNotFoundException("Highlight not found: " + highlightId);
        }
        return highlight;
    }

    private String blankToNull(String value) {
        return value != null && value.isBlank() ? null : value;
    }

    private String trimToNull(String value) {
        return value == null || value.isBlank() ? null : value.trim();
    }

    private AcademyProfileResponse toResponse(Academy a, List<HighlightResponse> highlights,
                                               List<FeaturedTrainerResponse> featuredTrainers, List<BranchResponse> branches) {
        List<String> hiddenLinks = a.getHiddenLinks() == null ? List.of() : List.of(a.getHiddenLinks().split(","));
        return new AcademyProfileResponse(a.getId(), a.getName(), a.getTagline(), a.getLogoUrl(), a.getDescription(),
                a.getEstablishedBy(), a.getOwnerName(), a.getAdditionalInfo(), a.getAddress(), a.getArea(), a.getCity(),
                a.getState(), a.getPinCode(), a.getContactNumber(), a.getEmail(), a.getInstagramUrl(), a.getXUrl(),
                a.getFacebookUrl(), a.getYoutubeUrl(), a.getWhatsapp(), a.getWebsiteUrl(), a.getMapsUrl(),
                a.getCoverImageUrl(), a.getCoverStyle(), a.getLogoColor(), hiddenLinks,
                highlights, featuredTrainers, branches);
    }
}
