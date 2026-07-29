package com.nest.app.platform.repository;

import com.nest.app.platform.entity.DeviceInstall;
import org.springframework.data.jpa.repository.JpaRepository;

import java.time.Instant;

public interface DeviceInstallRepository extends JpaRepository<DeviceInstall, String> {

    long countByFirstSeenAtAfter(Instant since);
}
