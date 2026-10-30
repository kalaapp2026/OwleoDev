package com.nest.app.enrolment.controller;

import com.nest.app.enrolment.dto.CourseChangeResponse;
import com.nest.app.enrolment.dto.CreateCourseChangeRequest;
import com.nest.app.enrolment.service.CourseChangeService;
import com.nest.common.security.FeatureKey;
import com.nest.common.security.RequiresFeature;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.UUID;

/**
 * A student's scheduled move from one course to another (Basic to Advanced from next month). The
 * service checks the permission on BOTH courses; the annotation is only the coarse gate.
 */
@RestController
@Tag(name = "Course changes")
public class CourseChangeController {

    private final CourseChangeService courseChangeService;

    public CourseChangeController(CourseChangeService courseChangeService) {
        this.courseChangeService = courseChangeService;
    }

    @PostMapping("/students/{membershipId}/course-changes")
    @RequiresFeature(FeatureKey.STUDENT_REGISTRATION)
    public CourseChangeResponse schedule(@PathVariable UUID membershipId,
                                         @Valid @RequestBody CreateCourseChangeRequest request) {
        return courseChangeService.schedule(membershipId, request);
    }

    @GetMapping("/students/{membershipId}/course-changes")
    @RequiresFeature(FeatureKey.STUDENT_REGISTRATION)
    public List<CourseChangeResponse> pending(@PathVariable UUID membershipId) {
        return courseChangeService.pendingFor(membershipId);
    }

    @DeleteMapping("/course-changes/{id}")
    @RequiresFeature(FeatureKey.STUDENT_REGISTRATION)
    public void cancel(@PathVariable UUID id) {
        courseChangeService.cancel(id);
    }
}
