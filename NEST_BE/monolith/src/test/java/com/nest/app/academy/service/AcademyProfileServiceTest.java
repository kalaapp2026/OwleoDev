package com.nest.app.academy.service;

import com.nest.app.academy.dto.FeaturedTrainerResponse;
import com.nest.app.academy.dto.UpdateFeaturedTrainerRequest;
import com.nest.app.academy.entity.AcademyFeaturedTrainer;
import com.nest.app.academy.repository.AcademyBranchRepository;
import com.nest.app.academy.repository.AcademyFeaturedTrainerRepository;
import com.nest.app.academy.repository.AcademyHighlightImageRepository;
import com.nest.app.academy.repository.AcademyHighlightRepository;
import com.nest.app.academy.repository.AcademyRepository;
import com.nest.app.identity.entity.AcademyMembership;
import com.nest.app.identity.entity.User;
import com.nest.app.identity.repository.AcademyMembershipRepository;
import com.nest.app.identity.repository.UserRepository;
import com.nest.app.storage.FileStorageService;
import com.nest.common.exception.ResourceNotFoundException;
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
import static org.mockito.Mockito.when;

/** Covers the one piece of real logic AcademyProfileService.updateFeaturedTrainer adds: the
 * designation round-trips, and a featured-trainer row from a DIFFERENT academy can't be edited
 * through this academy's id (the same ownership-check shape deleteFeaturedTrainer already had). */
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

    private AcademyProfileService service;

    private final UUID academyId = UUID.randomUUID();
    private final UUID trainerMembershipId = UUID.randomUUID();
    private final UUID userId = UUID.randomUUID();

    @BeforeEach
    void setUp() {
        service = new AcademyProfileService(academyRepository, highlightRepository, highlightImageRepository,
                featuredTrainerRepository, branchRepository, membershipRepository, userRepository, fileStorageService);
    }

    @Test
    void designationRoundTripsOnUpdate() {
        UUID featuredId = UUID.randomUUID();
        AcademyFeaturedTrainer featured = AcademyFeaturedTrainer.builder()
                .id(featuredId).academyId(academyId).trainerMembershipId(trainerMembershipId).build();
        when(featuredTrainerRepository.findById(featuredId)).thenReturn(java.util.Optional.of(featured));
        when(featuredTrainerRepository.save(featured)).thenReturn(featured);

        AcademyMembership membership = AcademyMembership.builder()
                .id(trainerMembershipId).academyId(academyId).userId(userId).roleType(Role.TRAINER).build();
        when(membershipRepository.findAllById(setOf(trainerMembershipId))).thenReturn(List.of(membership));
        User user = User.builder().id(userId).fullName("Meera Krishnan").build();
        when(userRepository.findAllById(setOf(userId))).thenReturn(List.of(user));

        FeaturedTrainerResponse result = service.updateFeaturedTrainer(academyId, featuredId,
                new UpdateFeaturedTrainerRequest("Head of Dance & Founder"));

        assertThat(result.designation()).isEqualTo("Head of Dance & Founder");
        assertThat(featured.getDesignation()).isEqualTo("Head of Dance & Founder");
    }

    @Test
    void aFeaturedTrainerFromAnotherAcademyCannotBeUpdated() {
        UUID featuredId = UUID.randomUUID();
        AcademyFeaturedTrainer featured = AcademyFeaturedTrainer.builder()
                .id(featuredId).academyId(UUID.randomUUID()).trainerMembershipId(trainerMembershipId).build();
        when(featuredTrainerRepository.findById(featuredId)).thenReturn(java.util.Optional.of(featured));

        assertThatThrownBy(() -> service.updateFeaturedTrainer(academyId, featuredId, new UpdateFeaturedTrainerRequest("x")))
                .isInstanceOf(ResourceNotFoundException.class);
    }

    private static java.util.Set<UUID> setOf(UUID id) {
        return java.util.Set.of(id);
    }
}
