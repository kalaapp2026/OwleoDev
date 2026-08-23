package com.nest.app.identity.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

/** @param languagePreference BCP 47 tag ("en", "hi", "pt-BR"). Not validated against a fixed list
 * on purpose - the client owns which locales it actually bundles, and the shipped set changes as
 * translations land. An unrecognised tag makes the client fall back to English. */
public record LanguageUpdateRequest(@NotBlank @Size(max = 10) String languagePreference) {
}
