package com.nest.app.notification.service;

import com.nest.app.identity.repository.AcademyMembershipRepository;
import com.nest.app.identity.repository.UserRepository;
import com.nest.app.notification.repository.AppNotificationRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.time.Duration;
import java.time.Instant;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class NotificationRetentionTest {

    @Mock private AppNotificationRepository repository;
    @Mock private UserRepository userRepository;
    @Mock private AcademyMembershipRepository membershipRepository;

    private NotificationService service;

    @BeforeEach
    void setUp() {
        service = new NotificationService(repository, userRepository, membershipRepository);
    }

    @Test
    void theJobClearsEverythingOlderThanSixtyDays() {
        Instant now = Instant.parse("2026-10-24T03:30:00Z");
        when(repository.deleteCreatedBefore(now.minus(Duration.ofDays(60)))).thenReturn(7);

        assertEquals(7, new NotificationRetentionJob(service, 60).run(now));

        ArgumentCaptor<Instant> cutoff = ArgumentCaptor.forClass(Instant.class);
        verify(repository).deleteCreatedBefore(cutoff.capture());
        assertEquals(Instant.parse("2026-08-25T03:30:00Z"), cutoff.getValue());
    }
}
