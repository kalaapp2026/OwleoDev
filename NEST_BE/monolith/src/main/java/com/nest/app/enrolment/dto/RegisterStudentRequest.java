package com.nest.app.enrolment.dto;

import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Past;

import java.time.LocalDate;
import java.util.List;

/** PRD 3.4 Flow A - manual/walk-in registration. */
public record RegisterStudentRequest(
        @NotBlank String username,
        @NotBlank String fullName,
        @NotBlank String phone,
        @Past @NotNull LocalDate dob,
        @Email String email,
        String address,
        String city,
        String state,
        @NotEmpty List<CourseFeeSelection> courses,
        /** The rest of the enrolment form. Optional as a whole - an older client omits it and
         * registration still works exactly as before. */
        PersonDetails details
) {
}
