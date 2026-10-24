package com.nest.app.enrolment.dto;

import com.nest.app.validation.PersonName;
import com.nest.app.validation.Phone;
import com.nest.app.validation.StrictEmail;
import jakarta.validation.Valid;

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
        @NotBlank @PersonName String fullName,
        @NotBlank @Phone String phone,
        @Past @NotNull LocalDate dob,
        @StrictEmail String email,
        String address,
        String city,
        String state,
        @NotEmpty List<CourseFeeSelection> courses,

        /** The extended profile fields. Null leaves every one of them as it was. */
        @Valid PersonDetails details
) {
}
