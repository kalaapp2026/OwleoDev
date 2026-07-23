package com.nest.app.enrolment.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;

import java.util.UUID;

/** PRD 7.4 - the OTP code the student read out to the Admin/Trainer completing their walk-in
 * registration, confirming they approve being linked to this second academy/course. Keyed by
 * membershipId (returned from the initial /students call) rather than phone, since phone is no
 * longer a unique identifier and could otherwise resolve to the wrong account. */
public record ConfirmMembershipRequest(
        @NotNull UUID membershipId,
        @NotBlank @Pattern(regexp = "\\d{4,8}") String code
) {
}
