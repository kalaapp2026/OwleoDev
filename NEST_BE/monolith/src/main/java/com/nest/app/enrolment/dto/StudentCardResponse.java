package com.nest.app.enrolment.dto;

import java.time.LocalDate;
import java.util.List;
import java.util.UUID;

/** The public-safe subset of a student's profile - what an Admin or any Trainer in the academy
 * can open regardless of which features they hold, mirroring {@link TrainerCardResponse}. The
 * profile screen's Fees/Attendance sections layer on top of this using their own feature-gated
 * endpoints; this card is identity-only. */
public record StudentCardResponse(
        UUID membershipId,
        String fullName,
        String photoUrl,
        String phone,
        String email,
        LocalDate dob,
        String guardianName,
        String address,
        String city,
        String state,
        LocalDate joiningDate,
        List<EnrolledCourse> courses
) {
    public record EnrolledCourse(UUID courseId, String courseName, String batchName) {
    }
}
