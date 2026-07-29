package com.nest.app.platform.controller;

import com.nest.app.platform.dto.DevicePingRequest;
import com.nest.app.platform.service.DeviceInstallService;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

@RestController
@Tag(name = "Platform (Super Admin)")
public class DeviceController {

    private final DeviceInstallService deviceInstallService;

    public DeviceController(DeviceInstallService deviceInstallService) {
        this.deviceInstallService = deviceInstallService;
    }

    /**
     * Called once per app launch, before login - which is the point, since an install that never
     * signs up should still be counted. Authenticated users hit it too; it's idempotent per device.
     */
    @PostMapping("/devices/ping")
    public void ping(@Valid @RequestBody DevicePingRequest request) {
        deviceInstallService.ping(request.deviceId(), request.platform(), request.appVersion());
    }
}
