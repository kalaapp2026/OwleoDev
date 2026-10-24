package com.nest.app.profile.dto;

import com.nest.app.validation.PersonName;
import com.nest.app.validation.Phone;
import com.nest.app.validation.PostalCode;
import jakarta.validation.constraints.Size;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Past;

import java.time.LocalDate;

/** What a person may change about themselves. Username and email are identity keys and stay out. */
public record UpdateSelfProfileRequest(
        @NotBlank @PersonName String fullName,
        @Phone(mobileOnly = false) String altPhone,
        @Past LocalDate dob,
        String gender,
        String bloodGroup,
        @PersonName String guardianName,
        @Size(max = 160) String addressLine1,
        @Size(max = 160) String addressLine2,
        @Size(max = 80) String landmark,
        @Size(max = 100) String city,
        @Size(max = 100) String district,
        @Size(max = 100) String state,
        @PostalCode String pinCode
) {
}
