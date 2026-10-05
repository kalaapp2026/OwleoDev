package com.nest.app.profile.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Past;

import java.time.LocalDate;

/** What a person may change about themselves. Username and email are identity keys and stay out. */
public record UpdateSelfProfileRequest(
        @NotBlank String fullName,
        String altPhone,
        @Past LocalDate dob,
        String gender,
        String bloodGroup,
        String guardianName,
        String addressLine1,
        String addressLine2,
        String landmark,
        String city,
        String district,
        String state,
        String pinCode
) {
}
