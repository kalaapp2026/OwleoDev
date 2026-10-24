package com.nest.app.academy.service;

import com.nest.app.academy.dto.UpdateAcademyProfileRequest;
import com.nest.app.academy.entity.Academy;
import com.nest.app.curriculum.repository.CourseRepository;
import com.nest.app.identity.repository.CourseMapRepository;
import com.nest.common.exception.BadRequestException;
import com.nest.common.exception.ConflictException;
import com.nest.app.academy.repository.AcademyBranchRepository;
import com.nest.app.academy.repository.AcademyFeaturedTrainerRepository;
import com.nest.app.academy.repository.AcademyHighlightImageRepository;
import com.nest.app.academy.repository.AcademyHighlightRepository;
import com.nest.app.academy.repository.AcademyRepository;
import com.nest.app.identity.entity.AcademyMembership;
import com.nest.app.identity.repository.AcademyMembershipRepository;
import com.nest.app.identity.repository.UserRepository;
import com.nest.app.storage.FileStorageService;
import com.nest.common.security.Role;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.List;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/** The academy profile's write rules: unique names per city, known links only, and a featured list
 * that never takes another academy's trainer. */
@ExtendWith(MockitoExtension.class)
class AcademyProfileServiceTest {

    @Mock
    private AcademyRepository academyRepository;
    @Mock
    private AcademyHighlightRepository highlightRepository;
    @Mock
    private AcademyHighlightImageRepository highlightImageRepository;
    @Mock
    private AcademyFeaturedTrainerRepository featuredTrainerRepository;
    @Mock
    private AcademyBranchRepository branchRepository;
    @Mock
    private AcademyMembershipRepository membershipRepository;
    @Mock
    private UserRepository userRepository;
    @Mock
    private FileStorageService fileStorageService;
    @Mock
    private CourseMapRepository courseMapRepository;
    @Mock
    private CourseRepository courseRepository;

    private AcademyProfileService service;

    private final UUID academyId = UUID.randomUUID();
    private final UUID trainerMembershipId = UUID.randomUUID();
    private final UUID userId = UUID.randomUUID();

    @BeforeEach
    void setUp() {
        service = new AcademyProfileService(academyRepository, highlightRepository, highlightImageRepository,
                featuredTrainerRepository, branchRepository, membershipRepository, userRepository, fileStorageService,
                courseMapRepository, courseRepository);
    }

    @Test
    void renamingOntoAnotherAcademysNameInTheSameCityIsRejected() {
        Academy academy = academy();
        when(academyRepository.findById(academyId)).thenReturn(java.util.Optional.of(academy));
        when(academyRepository.existsByNameIgnoreCaseAndCityIgnoreCaseAndIdNot("Rival Academy", "Bengaluru", academyId))
                .thenReturn(true);

        assertThatThrownBy(() -> service.updateProfile(academyId, request("Rival Academy", null, null)))
                .isInstanceOf(ConflictException.class);
        assertThat(academy.getName()).isEqualTo("Owleo");
    }

    @Test
    void publishStoresOnlyKnownHiddenLinksAndClearsRemovedPhotos() {
        Academy academy = academy();
        academy.setLogoUrl("/files/logo.png");
        academy.setCoverImageUrl("/files/cover.png");
        when(academyRepository.findById(academyId)).thenReturn(java.util.Optional.of(academy));

        service.updateProfile(academyId, new UpdateAcademyProfileRequest(null, "t", "d", null, null, null, "24 Road",
                "Indiranagar", null, null, "560038", "98450", null, null, null, null, null, null, null, null,
                "gold", "violet", List.of("instagram", "bogus", "maps", "instagram"), true, true, null));

        assertThat(academy.getHiddenLinks()).isEqualTo("instagram,maps");
        assertThat(academy.getLogoUrl()).isNull();
        assertThat(academy.getCoverImageUrl()).isNull();
        assertThat(academy.getCoverStyle()).isEqualTo("gold");
        assertThat(academy.getArea()).isEqualTo("Indiranagar");
        assertThat(academy.getName()).isEqualTo("Owleo");
        verify(featuredTrainerRepository, never()).deleteAll(any());
    }

    @Test
    void aFeaturedListNamingAnotherAcademysTrainerLeavesTheOldListAlone() {
        when(academyRepository.findById(academyId)).thenReturn(java.util.Optional.of(academy()));
        AcademyMembership foreign = AcademyMembership.builder()
                .id(trainerMembershipId).academyId(UUID.randomUUID()).userId(userId).roleType(Role.TRAINER).build();
        when(membershipRepository.findAllById(setOf(trainerMembershipId))).thenReturn(List.of(foreign));

        var entries = List.of(new UpdateAcademyProfileRequest.FeaturedTrainerEntry(trainerMembershipId, "Head"));
        assertThatThrownBy(() -> service.updateProfile(academyId, request(null, null, entries)))
                .isInstanceOf(BadRequestException.class);
        verify(featuredTrainerRepository, never()).deleteAll(any());
    }

    private Academy academy() {
        return Academy.builder().id(academyId).name("Owleo").city("Bengaluru").state("Karnataka")
                .address("x").contactNumber("1").build();
    }

    private static UpdateAcademyProfileRequest request(String name, String city,
                                                       List<UpdateAcademyProfileRequest.FeaturedTrainerEntry> featured) {
        return new UpdateAcademyProfileRequest(name, null, null, null, null, null, null, null, city, null, null, null,
                null, null, null, null, null, null, null, null, null, null, null, null, null, featured);
    }

    private static java.util.Set<UUID> setOf(UUID id) {
        return java.util.Set.of(id);
    }
}
