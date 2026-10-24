package com.nest.app.enrolment.dto;

import com.nest.app.validation.Username;
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
import java.util.UUID;

/** PRD 3.4 Flow A - manual/walk-in registration. */
public record RegisterStudentRequest(
        @NotBlank @Username String username,
        @NotBlank @PersonName String fullName,
        @NotBlank @Phone String phone,
        @Past @NotNull LocalDate dob,
        @StrictEmail String email,
        String address,
        String city,
        String state,
        @NotEmpty List<CourseFeeSelection> courses,
        /** The rest of the enrolment form. Optional as a whole - an older client omits it and
         * registration still works exactly as before. */
        @Valid PersonDetails details,
        /** Present when the creator already verified, with the person's own code, that this email's
         * existing account agrees to join - see ExistingAccountService. Null otherwise. */
        UUID linkGrantId
) {
    /** The shape before {@code linkGrantId} existed - kept so older callers needn't pass a null. */
    public RegisterStudentRequest(String username, String fullName, String phone, LocalDate dob, String email,
                                  String address, String city, String state, List<CourseFeeSelection> courses,
                                  PersonDetails details) {
        this(username, fullName, phone, dob, email, address, city, state, courses, details, null);
    }
}
