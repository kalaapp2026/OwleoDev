package com.nest.identity.dto;

import com.nest.identity.entity.ThemePreference;
import jakarta.validation.constraints.NotNull;

public record ThemeUpdateRequest(@NotNull ThemePreference themePreference) {
}
