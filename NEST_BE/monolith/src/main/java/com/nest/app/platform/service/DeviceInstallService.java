package com.nest.app.platform.service;

import com.nest.app.platform.entity.DeviceInstall;
import com.nest.app.platform.repository.DeviceInstallRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;

@Service
public class DeviceInstallService {

    private final DeviceInstallRepository repository;

    public DeviceInstallService(DeviceInstallRepository repository) {
        this.repository = repository;
    }

    /** Upsert by device id: first ping creates the row (that's the "install"), later pings only
     * move last_seen_at, so the install count never inflates from repeat launches. */
    @Transactional
    public void ping(String deviceId, String platform, String appVersion) {
        Instant now = Instant.now();
        DeviceInstall install = repository.findById(deviceId).orElseGet(() -> DeviceInstall.builder()
                .deviceId(deviceId)
                .firstSeenAt(now)
                .build());
        install.setPlatform(platform);
        install.setAppVersion(appVersion);
        install.setLastSeenAt(now);
        repository.save(install);
    }
}
