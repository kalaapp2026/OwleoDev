package com.nest.app.enrolment.controller;

import com.nest.app.enrolment.dto.ConfirmMembershipRequest;
import com.nest.app.enrolment.dto.RegisterStudentRequest;
import com.nest.app.enrolment.dto.StudentResponse;
import com.nest.app.enrolment.dto.StudentSummaryResponse;
import com.nest.app.enrolment.service.StudentRegistrationService;
import com.nest.common.security.FeatureKey;
import com.nest.common.security.RequiresFeature;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
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

    /** Batch roster picker source - every active Student enrolled in this course. */
    @GetMapping("/courses/{courseId}/students")
    @RequiresFeature(FeatureKey.BATCH_CREATION)
    public List<StudentSummaryResponse> studentsForCourse(@PathVariable UUID courseId) {
        return studentRegistrationService.listStudentsForCourse(courseId);
    }
}
