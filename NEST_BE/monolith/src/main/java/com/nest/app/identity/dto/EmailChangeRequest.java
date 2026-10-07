package com.nest.app.identity.dto;

import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;

/** Both steps of changing the login email use this: {@code code} is blank when asking for the
 * code and required when confirming (the service rejects a blank code at that point). */
public record EmailChangeRequest(@NotBlank @Email String newEmail, String code) {
}
