package com.nest.app.enrolment.dto;

import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Past;

import java.time.LocalDate;
import java.util.List;

/** Student edit. Username is immutable so it isn't here. {@code courses} fully replaces the
 * enrolment + per-course fee set (dropped courses are unenrolled; the per-course active flag on
 * surviving courses is preserved). */
public record UpdateStudentRequest(
        @NotBlank String fullName,
        @NotBlank String phone,
        @Past @NotNull LocalDate dob,
        @Email String email,
        String address,
        String city,
        String state,
        @NotEmpty List<CourseFeeSelection> courses
) {
}
