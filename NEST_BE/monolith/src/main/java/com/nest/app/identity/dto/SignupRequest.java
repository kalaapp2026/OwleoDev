package com.nest.app.identity.dto;

import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

/** Public self-signup (PRD 7.4 addendum) - username and password are chosen together on the same
 * screen, unlike every admin-provisioned account (which gets a generated temp password instead). */
public record SignupRequest(
        @NotBlank String username,
        @NotBlank @Size(min = 6, message = "Password must be at least 6 characters") String password,
        @NotBlank String fullName,
        @NotBlank String phone,
        @Email @NotBlank String email
) {
}
