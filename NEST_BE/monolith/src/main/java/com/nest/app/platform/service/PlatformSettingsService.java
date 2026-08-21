package com.nest.app.platform.service;

import com.nest.app.platform.entity.AppMode;
import com.nest.app.platform.entity.PlatformSettings;
import com.nest.app.platform.repository.PlatformSettingsRepository;
import com.nest.common.audit.Auditable;
import com.nest.common.security.TenantContext;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;

@Service
public class PlatformSettingsService {

    private final PlatformSettingsRepository repository;

    public PlatformSettingsService(PlatformSettingsRepository repository) {
        this.repository = repository;
    }

    /**
     * The migration seeds the singleton row, so this normally just reads it. The fallback exists
     * because EVERY client calls this on startup to decide which half of the app to show - if the
     * row were somehow missing, throwing here would brick the app for everyone rather than
     * degrade to the documented default.
     */
    @Transactional(readOnly = true)
    public PlatformSettings current() {
        return repository.findById(PlatformSettings.SINGLETON_ID)
                .orElseGet(() -> PlatformSettings.builder().appMode(AppMode.ERP_FIRST).build());
    }

    @Transactional
    @Auditable(action = "PLATFORM_APP_MODE_CHANGED", entityType = "platform_settings")
    public PlatformSettings updateAppMode(AppMode appMode) {
        PlatformSettings settings = repository.findById(PlatformSettings.SINGLETON_ID)
                .orElseGet(() -> PlatformSettings.builder().build());
        settings.setAppMode(appMode);
        settings.setUpdatedAt(Instant.now());
        settings.setUpdatedBy(TenantContext.currentUserId());
        return repository.save(settings);
    }
}
