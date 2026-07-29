package com.nest.app.platform.entity;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

import java.time.Instant;

/**
 * One row per distinct device that has ever launched the app - the honest proxy for "how many
 * installs are out there", since the backend genuinely cannot read Play Store / App Store download
 * counts (those live in the store consoles). It undercounts reinstalls on the same device and
 * overcounts one person using a phone and a tablet, which is why the Super Admin console labels
 * this "installs seen" rather than "downloads".
 */
@Entity
@Table(name = "device_installs")
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class DeviceInstall {

    /** Client-generated, stored once on the device - not a hardware id, so it carries no PII. */
    @Id
    @Column(name = "device_id", length = 128)
    private String deviceId;

    @Column(length = 20)
    private String platform;

    @Column(name = "app_version", length = 40)
    private String appVersion;

    @Column(name = "first_seen_at", nullable = false)
    private Instant firstSeenAt;

    @Column(name = "last_seen_at", nullable = false)
    private Instant lastSeenAt;
}
