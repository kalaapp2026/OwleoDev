package com.nest.app.enrolment.controller;

import com.nest.app.enrolment.dto.ConfirmMembershipRequest;
import com.nest.app.enrolment.dto.RegisterStudentRequest;
import com.nest.app.enrolment.dto.StudentDetailResponse;
import com.nest.app.enrolment.dto.StudentResponse;
import com.nest.app.enrolment.dto.StudentSummaryResponse;
import com.nest.app.enrolment.dto.UpdateStudentRequest;
import com.nest.app.enrolment.service.StudentRegistrationService;
import com.nest.common.security.FeatureKey;
import com.nest.common.security.RequiresFeature;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.Map;
import java.util.UUID;

@RestController
@Tag(name = "Students")
public class StudentController {

    private final StudentRegistrationService studentRegistrationService;

    public StudentController(StudentRegistrationService studentRegistrationService) {
        this.studentRegistrationService = studentRegistrationService;
    }

    /** If the phone number belongs to an existing NEST user joining a new academy, the returned
     * membership is PENDING_CONFIRMATION (pendingConfirmation=true) and {@link #confirmMembership}
     * must be called before it grants any access (PRD 7.4). */
    @PostMapping("/students")
    @RequiresFeature(FeatureKey.STUDENT_REGISTRATION)
    public StudentResponse register(@Valid @RequestBody RegisterStudentRequest request) {
        return studentRegistrationService.registerManual(request);
    }

    @PostMapping("/students/confirm-membership")
    @RequiresFeature(FeatureKey.STUDENT_REGISTRATION)
    public StudentResponse confirmMembership(@Valid @RequestBody ConfirmMembershipRequest request) {
        return studentRegistrationService.confirmMembership(request);
    }

    /** Pre-fills the student edit form (profile + per-course fees). */
    @GetMapping("/students/{membershipId}")
    @RequiresFeature(FeatureKey.STUDENT_REGISTRATION)
    public StudentDetailResponse detail(@PathVariable UUID membershipId) {
        return studentRegistrationService.getStudentDetail(membershipId);
    }

    @PutMapping("/students/{membershipId}")
    @RequiresFeature(FeatureKey.STUDENT_REGISTRATION)
    public StudentResponse update(@PathVariable UUID membershipId, @Valid @RequestBody UpdateStudentRequest request) {
        return studentRegistrationService.updateStudent(membershipId, request);
    }

    /** Batch roster picker + Users management screen. includeInactive=false (default, batch picker)
     * drops course-deactivated students; true (management view) keeps them so they can be flipped
     * back on. */
    @GetMapping("/courses/{courseId}/students")
    @RequiresFeature(FeatureKey.BATCH_CREATION)
    public List<StudentSummaryResponse> studentsForCourse(@PathVariable UUID courseId,
                                                          @RequestParam(defaultValue = "false") boolean includeInactive) {
        return studentRegistrationService.listStudentsForCourse(courseId, includeInactive);
    }

    /** Academy Admin (or Trainer with STUDENT_REGISTRATION) deactivates/reactivates a person for
     * this one course - works for both students and trainers, since both live in course_map. */
    @PutMapping("/courses/{courseId}/members/{membershipId}/active")
    @RequiresFeature(FeatureKey.STUDENT_REGISTRATION)
    public ResponseEntity<Void> setCourseMemberActive(@PathVariable UUID courseId, @PathVariable UUID membershipId,
                                                      @RequestParam boolean active) {
        studentRegistrationService.setCourseMemberActive(courseId, membershipId, active);
        return ResponseEntity.noContent().build();
    }

    /** Issues a fresh temp password for a student (unified login: students log in with a password
     * now) - returned once so the admin can hand it over. The student changes it on first login. */
    @PostMapping("/students/{membershipId}/reset-password")
    @RequiresFeature(FeatureKey.STUDENT_REGISTRATION)
    public Map<String, String> resetPassword(@PathVariable UUID membershipId) {
        return Map.of("temporaryPassword", studentRegistrationService.resetStudentPassword(membershipId));
    }
}
