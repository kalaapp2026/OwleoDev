package com.nest.app.platform.dto;

import com.nest.app.platform.entity.AppMode;
import jakarta.validation.constraints.NotNull;

public final class PlatformSettingsDtos {

    private PlatformSettingsDtos() {
    }

    /**
     * @param allowsBoth  whether the nav's centre toggle does anything - false means one half is
     *                    hidden entirely and the toggle should not be shown at all.
     * @param startsOnErp which half to open on.
     */
    public record Response(AppMode appMode, boolean allowsErp, boolean allowsSocial,
                           boolean allowsBoth, boolean startsOnErp) {}

    public record UpdateRequest(@NotNull AppMode appMode) {}
}
