package com.nest.app.platform.service;

import com.nest.app.platform.entity.AppMode;
import com.nest.app.platform.entity.PlatformSettings;
import com.nest.app.platform.repository.PlatformSettingsRepository;
import com.nest.common.security.NestPrincipal;
import com.nest.common.security.Role;
import com.nest.common.security.TenantContext;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.when;

class AppModeSemanticsTest {

    @Test
    void erpFirstShowsBothAndOpensOnErp() {
        AppMode mode = AppMode.ERP_FIRST;
        assertThat(mode.allowsErp()).isTrue();
        assertThat(mode.allowsSocial()).isTrue();
        assertThat(mode.allowsBoth()).as("toggle stays available").isTrue();
        assertThat(mode.startsOnErp()).isTrue();
    }

    @Test
    void socialFirstShowsBothAndOpensOnSocial() {
        AppMode mode = AppMode.SOCIAL_FIRST;
        assertThat(mode.allowsBoth()).isTrue();
        assertThat(mode.startsOnErp()).isFalse();
    }

    @Test
    void erpOnlyHidesSocialAndTheToggle() {
        AppMode mode = AppMode.ERP_ONLY;
        assertThat(mode.allowsErp()).isTrue();
        assertThat(mode.allowsSocial()).as("Social is hidden entirely").isFalse();
        assertThat(mode.allowsBoth()).as("nothing to toggle to").isFalse();
        assertThat(mode.startsOnErp()).isTrue();
    }

    @Test
    void socialOnlyHidesErpAndTheToggle() {
        AppMode mode = AppMode.SOCIAL_ONLY;
        assertThat(mode.allowsErp()).isFalse();
        assertThat(mode.allowsSocial()).isTrue();
        assertThat(mode.allowsBoth()).isFalse();
        assertThat(mode.startsOnErp()).isFalse();
    }

    @Test
    void everyModeLeavesAtLeastOneHalfReachable() {
        for (AppMode mode : AppMode.values()) {
            assertThat(mode.allowsErp() || mode.allowsSocial())
                    .as("%s would leave users with a blank app", mode)
                    .isTrue();
        }
    }
}

@ExtendWith(MockitoExtension.class)
class PlatformSettingsServiceTest {

    @Mock
    private PlatformSettingsRepository repository;

    private PlatformSettingsService service;

    @BeforeEach
    void setUp() {
        service = new PlatformSettingsService(repository);
    }

    @AfterEach
    void tearDown() {
        TenantContext.clear();
    }

    @Test
    void readsTheStoredMode() {
        when(repository.findById(PlatformSettings.SINGLETON_ID))
                .thenReturn(Optional.of(PlatformSettings.builder().appMode(AppMode.SOCIAL_ONLY).build()));

        assertThat(service.current().getAppMode()).isEqualTo(AppMode.SOCIAL_ONLY);
    }

    @Test
    void fallsBackToErpFirstRatherThanFailingWhenTheRowIsMissing() {
        // Every client reads this on startup - throwing here would brick the app for everyone.
        when(repository.findById(PlatformSettings.SINGLETON_ID)).thenReturn(Optional.empty());

        assertThat(service.current().getAppMode()).isEqualTo(AppMode.ERP_FIRST);
    }

    @Test
    void updateRecordsWhoChangedIt() {
        UUID actor = UUID.randomUUID();
        TenantContext.set(new NestPrincipal(actor, "root", Role.SUPER_ADMIN, List.of(), null));
        when(repository.findById(PlatformSettings.SINGLETON_ID))
                .thenReturn(Optional.of(PlatformSettings.builder().appMode(AppMode.ERP_FIRST).build()));
        when(repository.save(any(PlatformSettings.class))).thenAnswer(inv -> inv.getArgument(0));

        PlatformSettings saved = service.updateAppMode(AppMode.ERP_ONLY);

        assertThat(saved.getAppMode()).isEqualTo(AppMode.ERP_ONLY);
        assertThat(saved.getUpdatedBy()).isEqualTo(actor);
    }
}
