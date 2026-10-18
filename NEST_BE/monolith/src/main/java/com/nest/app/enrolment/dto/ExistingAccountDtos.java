package com.nest.app.enrolment.dto;

import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;

import java.time.LocalDate;
import java.util.List;
import java.util.UUID;

/**
 * The "this email already has a NEST account" flow, run while the creator is still filling in the
 * form - check, send the person a code, check the code they read back - rather than discovering the
 * account only when Save is pressed.
 */
public final class ExistingAccountDtos {

    private ExistingAccountDtos() {
    }

    /** @param role {@code STUDENT} or {@code TRAINER} - what they would be added as. */
    public record CodeRequest(@NotBlank @Email String email, @NotBlank String role) {
    }

    public record VerifyRequest(@NotBlank @Email String email, @NotBlank String role, @NotBlank String code) {
    }

    /**
     * All the creator learns BEFORE the person has agreed: whether the account exists, a masked name
     * to recognise it by, and whether they are already at this academy. Nothing else - the profile
     * and other academies' courses wait for the person's own code.
     */
    public record CheckResponse(boolean exists, String maskedName, boolean alreadyAtThisAcademy, String roleHere) {
    }

    /** One academy the person belongs to, with the courses they are mapped to there. */
    public record Enrolment(String academyName, boolean thisAcademy, String role,
                            List<UUID> courseIds, List<String> courseNames) {
    }

    /**
     * What a verified code unlocks: the person's details to pre-fill the form with, every academy
     * and course they are already mapped to, and the single-use {@code linkGrantId} the registration
     * must present to be activated immediately instead of waiting on another code.
     */
    public record VerifiedResponse(UUID linkGrantId, UUID userId, String username, String fullName, String phone,
                                   String email, LocalDate dob, PersonDetails details, List<Enrolment> enrolments) {
    }
}
