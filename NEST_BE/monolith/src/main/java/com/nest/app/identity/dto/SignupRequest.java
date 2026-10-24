package com.nest.app.identity.dto;

import com.nest.app.validation.Username;
import com.nest.app.validation.StrongPassword;
import com.nest.app.validation.PersonName;
import com.nest.app.validation.Phone;
import com.nest.app.validation.StrictEmail;
import jakarta.validation.Valid;

import com.nest.app.enrolment.dto.PersonDetails;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Past;
import jakarta.validation.constraints.Size;

import java.time.LocalDate;

/** Public self-signup (PRD 7.4 addendum) - username and password are chosen together on the same
 * screen, unlike every admin-provisioned account (which gets a generated temp password instead).
 * {@code dob} and {@code details} are optional: the account is created from just the first five
 * fields either way, the same as before this pair existed - {@link PersonDetails} is the same
 * shared, all-optional record the staff-side student/trainer registration forms use, so a person
 * filling in the same "extra details" on their own signup goes through one merge path either way
 * (see IdentityRegistrationService#applyPersonDetails). */
public record SignupRequest(
        @NotBlank @Username String username,
        @NotBlank @StrongPassword String password,
        @NotBlank @PersonName String fullName,
        @NotBlank @Phone String phone,
        @StrictEmail @NotBlank String email,
        @Past LocalDate dob,
        @Valid PersonDetails details
) {
}
