package com.nest.app.platform.entity;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

import java.time.Instant;
import java.util.UUID;

/** Singleton row (id is pinned to 1 by a CHECK constraint) holding platform-wide configuration. */
@Entity
@Table(name = "platform_settings")
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class PlatformSettings {

    public static final short SINGLETON_ID = 1;

    @Id
    @Builder.Default
    private Short id = SINGLETON_ID;

    @Enumerated(EnumType.STRING)
    @Column(name = "app_mode", nullable = false, length = 20)
    @Builder.Default
    private AppMode appMode = AppMode.ERP_FIRST;

    @Column(name = "updated_at", nullable = false)
    @Builder.Default
    private Instant updatedAt = Instant.now();

    @Column(name = "updated_by")
    private UUID updatedBy;
}
