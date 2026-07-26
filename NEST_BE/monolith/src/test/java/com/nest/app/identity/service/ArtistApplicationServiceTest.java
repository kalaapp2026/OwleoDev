package com.nest.app.identity.service;

import com.nest.app.identity.entity.ArtistApplication;
import com.nest.app.identity.entity.ArtistApplicationStatus;
import com.nest.app.identity.entity.User;
import com.nest.app.identity.repository.ArtistApplicationRepository;
import com.nest.app.identity.repository.UserRepository;
import com.nest.app.notification.service.NotificationService;
import com.nest.common.exception.BadRequestException;
import com.nest.common.security.NestPrincipal;
import com.nest.common.security.Role;
import com.nest.common.security.TenantContext;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class ArtistApplicationServiceTest {

    @Mock
    private ArtistApplicationRepository applicationRepository;
    @Mock
    private UserRepository userRepository;
    @Mock
    private NotificationService notificationService;

    private ArtistApplicationService service;
    private final UUID userId = UUID.randomUUID();

    @AfterEach
    void tearDown() {
        TenantContext.clear();
    }

    private void newService() {
        service = new ArtistApplicationService(applicationRepository, userRepository, notificationService);
        TenantContext.set(new NestPrincipal(userId, "guest_x", Role.GUEST, List.of(), null));
    }

    @Test
    void guestCanApply() {
        newService();
        User guest = User.builder().id(userId).username("guest_x").fullName("Guest X").role(Role.GUEST).build();
        when(userRepository.findById(userId)).thenReturn(Optional.of(guest));
        when(applicationRepository.findFirstByUserIdAndStatusOrderByCreatedAtDesc(userId, ArtistApplicationStatus.PENDING))
                .thenReturn(Optional.empty());
        when(applicationRepository.save(any(ArtistApplication.class))).thenAnswer(inv -> {
            ArtistApplication a = inv.getArgument(0);
            a.setId(UUID.randomUUID());
            return a;
        });
        when(userRepository.findByRole(Role.SUPER_ADMIN)).thenReturn(List.of());

        var response = service.apply();

        assertThat(response.status()).isEqualTo(ArtistApplicationStatus.PENDING);
    }

    @Test
    void alreadyArtistCannotReapply() {
        newService();
        User artist = User.builder().id(userId).username("artist_x").role(Role.ARTIST).build();
        when(userRepository.findById(userId)).thenReturn(Optional.of(artist));

        assertThatThrownBy(() -> service.apply()).isInstanceOf(BadRequestException.class);
    }

    @Test
    void cannotApplyTwiceWhilePending() {
        newService();
        User guest = User.builder().id(userId).username("guest_x").role(Role.GUEST).build();
        when(userRepository.findById(userId)).thenReturn(Optional.of(guest));
        when(applicationRepository.findFirstByUserIdAndStatusOrderByCreatedAtDesc(userId, ArtistApplicationStatus.PENDING))
                .thenReturn(Optional.of(ArtistApplication.builder().id(UUID.randomUUID()).userId(userId).build()));

        assertThatThrownBy(() -> service.apply()).isInstanceOf(BadRequestException.class);
    }

    @Test
    void approvePromotesTheUserToArtist() {
        service = new ArtistApplicationService(applicationRepository, userRepository, notificationService);
        TenantContext.set(new NestPrincipal(UUID.randomUUID(), "root", Role.SUPER_ADMIN, List.of(), null));

        UUID applicationId = UUID.randomUUID();
        ArtistApplication application = ArtistApplication.builder().id(applicationId).userId(userId)
                .status(ArtistApplicationStatus.PENDING).build();
        User guest = User.builder().id(userId).username("guest_x").fullName("Guest X").role(Role.GUEST).build();
        when(applicationRepository.findById(applicationId)).thenReturn(Optional.of(application));
        when(userRepository.findById(userId)).thenReturn(Optional.of(guest));

        var response = service.approve(applicationId);

        assertThat(guest.getRole()).isEqualTo(Role.ARTIST);
        assertThat(response.status()).isEqualTo(ArtistApplicationStatus.APPROVED);
    }

    @Test
    void cannotDecideAnAlreadyDecidedApplication() {
        service = new ArtistApplicationService(applicationRepository, userRepository, notificationService);
        TenantContext.set(new NestPrincipal(UUID.randomUUID(), "root", Role.SUPER_ADMIN, List.of(), null));

        UUID applicationId = UUID.randomUUID();
        ArtistApplication decided = ArtistApplication.builder().id(applicationId).userId(userId)
                .status(ArtistApplicationStatus.REJECTED).build();
        when(applicationRepository.findById(applicationId)).thenReturn(Optional.of(decided));

        assertThatThrownBy(() -> service.approve(applicationId)).isInstanceOf(BadRequestException.class);
    }
}
