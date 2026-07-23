package com.nest.app.identity.dto;

import com.nest.app.identity.entity.ThemePreference;
import jakarta.validation.constraints.NotNull;

public record ThemeUpdateRequest(@NotNull ThemePreference themePreference) {
}
