package com.nest.app.identity.service;

import com.nest.app.identity.entity.AccountLinkGrant;
import com.nest.app.identity.repository.AcademyMembershipRepository;
import com.nest.app.identity.repository.AccountLinkGrantRepository;
import com.nest.app.identity.repository.CourseFeatureGrantRepository;
import com.nest.app.identity.repository.CourseMapRepository;
import com.nest.app.identity.repository.FeatureGrantRepository;
import com.nest.app.identity.repository.UserRepository;
import com.nest.common.crypto.PiiHasher;
import com.nest.common.exception.BadRequestException;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.security.crypto.password.PasswordEncoder;

import java.time.Duration;
import java.time.Instant;
import java.util.Optional;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/** A link grant is proof a person agreed to join one academy. It must be impossible to reuse it, let
 * it outlive its window, or carry it to a different person, academy or creator. */
@ExtendWith(MockitoExtension.class)
class LinkGrantTest {

    @Mock private UserRepository userRepository;
    @Mock private AcademyMembershipRepository membershipRepository;
    @Mock private FeatureGrantRepository featureGrantRepository;
    @Mock private CourseFeatureGrantRepository courseFeatureGrantRepository;
    @Mock private CourseMapRepository courseMapRepository;
    @Mock private PiiHasher hasher;
    @Mock private PasswordEncoder passwordEncoder;
    @Mock private TempPasswordGenerator tempPasswordGenerator;
    @Mock private AccountLinkGrantRepository accountLinkGrantRepository;

    private IdentityRegistrationService service;

    private final UUID userId = UUID.randomUUID();
    private final UUID academyId = UUID.randomUUID();
    private final UUID actorId = UUID.randomUUID();
    private final UUID grantId = UUID.randomUUID();

    @BeforeEach
    void setUp() {
        service = new IdentityRegistrationService(userRepository, membershipRepository, featureGrantRepository,
                courseFeatureGrantRepository, courseMapRepository, hasher, passwordEncoder, tempPasswordGenerator,
                accountLinkGrantRepository);
    }

    private AccountLinkGrant grant() {
        return AccountLinkGrant.builder().id(grantId).userId(userId).academyId(academyId).createdBy(actorId)
                .expiresAt(Instant.now().plus(Duration.ofMinutes(10))).build();
    }

    @Test
    void aMatchingFreshGrantIsAcceptedAndSpent() {
        AccountLinkGrant grant = grant();
        when(accountLinkGrantRepository.findById(grantId)).thenReturn(Optional.of(grant));

        assertThatCode(() -> service.consumeLinkGrant(grantId, userId, academyId, actorId)).doesNotThrowAnyException();

        assertThat(grant.isUsed()).isTrue();
        verify(accountLinkGrantRepository).save(grant);
    }

    @Test
    void aGrantCannotBeUsedTwice() {
        AccountLinkGrant grant = grant();
        grant.setUsed(true);
        when(accountLinkGrantRepository.findById(grantId)).thenReturn(Optional.of(grant));

        assertThatThrownBy(() -> service.consumeLinkGrant(grantId, userId, academyId, actorId))
                .isInstanceOf(BadRequestException.class);
    }

    @Test
    void anExpiredGrantIsRejected() {
        AccountLinkGrant grant = grant();
        grant.setExpiresAt(Instant.now().minusSeconds(1));
        when(accountLinkGrantRepository.findById(grantId)).thenReturn(Optional.of(grant));

        assertThatThrownBy(() -> service.consumeLinkGrant(grantId, userId, academyId, actorId))
                .isInstanceOf(BadRequestException.class);
        verify(accountLinkGrantRepository, never()).save(grant);
    }

    @Test
    void aGrantForADifferentPersonIsRejected() {
        when(accountLinkGrantRepository.findById(grantId)).thenReturn(Optional.of(grant()));

        assertThatThrownBy(() -> service.consumeLinkGrant(grantId, UUID.randomUUID(), academyId, actorId))
                .isInstanceOf(BadRequestException.class);
    }

    @Test
    void aGrantCannotBeCarriedToAnotherAcademy() {
        when(accountLinkGrantRepository.findById(grantId)).thenReturn(Optional.of(grant()));

        assertThatThrownBy(() -> service.consumeLinkGrant(grantId, userId, UUID.randomUUID(), actorId))
                .isInstanceOf(BadRequestException.class);
    }

    @Test
    void aGrantCannotBeUsedBySomeoneWhoDidNotVerifyIt() {
        when(accountLinkGrantRepository.findById(grantId)).thenReturn(Optional.of(grant()));

        assertThatThrownBy(() -> service.consumeLinkGrant(grantId, userId, academyId, UUID.randomUUID()))
                .isInstanceOf(BadRequestException.class);
    }

    @Test
    void anUnknownGrantIsRejected() {
        when(accountLinkGrantRepository.findById(grantId)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.consumeLinkGrant(grantId, userId, academyId, actorId))
                .isInstanceOf(BadRequestException.class);
    }
}
