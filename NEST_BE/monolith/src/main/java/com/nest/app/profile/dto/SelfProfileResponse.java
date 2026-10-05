package com.nest.app.profile.dto;

import java.time.Instant;
import java.time.LocalDate;
import java.util.List;
import java.util.UUID;

/** The signed-in person's own profile, unmasked - it is theirs. */
public record SelfProfileResponse(
        UUID userId,
        String username,
        String fullName,
        String email,
        String phone,
        String altPhone,
        LocalDate dob,
        String gender,
        String bloodGroup,
        String guardianName,
        String addressLine1,
        String addressLine2,
        String landmark,
        String city,
        String district,
        String state,
        String pinCode,
        String profileImageUrl,
        Instant onPlatformSince,
        List<AcademyEnrolment> academies
) {
    /** One academy the person belongs to, with what they are enrolled in there. */
    public record AcademyEnrolment(UUID academyId, String academyName, LocalDate joiningDate,
                                   List<Course> courses) {
    }

    public record Course(UUID courseId, String courseName, List<String> trainers) {
    }
}
