package com.nest.academy.service;

import com.nest.academy.client.IdentityAdminProvisionResponse;
import com.nest.academy.client.IdentityServiceClient;
import com.nest.academy.dto.OnboardAcademyRequest;
import com.nest.academy.entity.Academy;
import com.nest.academy.entity.AcademyCategory;
import com.nest.academy.repository.AcademyRepository;
import com.nest.common.exception.ConflictException;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class AcademyServiceTest {

    @Mock
    private AcademyRepository academyRepository;
    @Mock
    private IdentityServiceClient identityServiceClient;

    private AcademyService academyService;

    private static final OnboardAcademyRequest REQUEST = new OnboardAcademyRequest(
            "Natyalaya", AcademyCategory.DANCE, null, "12 MG Road", "Bengaluru", "Karnataka",
            "9876543210", "owner@natyalaya.example", "STANDARD",
            "meera_admin", "Meera", "9123456780", "meera@natyalaya.example"
    );

    @BeforeEach
    void setUp() {
        academyService = new AcademyService(academyRepository, identityServiceClient);
    }

    @Test
    void duplicateNameAndCityIsRejectedBeforeCallingIdentityService() {
        when(academyRepository.existsByNameIgnoreCaseAndCityIgnoreCase("Natyalaya", "Bengaluru")).thenReturn(true);

        assertThatThrownBy(() -> academyService.onboardAcademy(REQUEST))
                .isInstanceOf(ConflictException.class);

        verify(identityServiceClient, never()).provisionAcademyAdmin(any());
    }

    @Test
    void onboardingCreatesAcademyAndProvisionsAdmin() {
        when(academyRepository.existsByNameIgnoreCaseAndCityIgnoreCase("Natyalaya", "Bengaluru")).thenReturn(false);
        when(academyRepository.save(any(Academy.class))).thenAnswer(inv -> {
            Academy a = inv.getArgument(0);
            a.setId(UUID.randomUUID());
            return a;
        });
        when(identityServiceClient.provisionAcademyAdmin(any()))
                .thenReturn(new IdentityAdminProvisionResponse(UUID.randomUUID(), UUID.randomUUID(), "meera_admin", "TempPass123"));

        var response = academyService.onboardAcademy(REQUEST);

        assertThat(response.academy().name()).isEqualTo("Natyalaya");
        assertThat(response.adminUsername()).isEqualTo("meera_admin");
        assertThat(response.adminTemporaryPassword()).isEqualTo("TempPass123");
    }
}
