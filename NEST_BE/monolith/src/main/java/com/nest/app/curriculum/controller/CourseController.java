package com.nest.app.curriculum.controller;

import com.nest.app.curriculum.dto.CourseResponse;
import com.nest.app.curriculum.dto.CreateCourseRequest;
import com.nest.app.curriculum.dto.UpdateCourseRequest;
import com.nest.app.curriculum.entity.CourseStatus;
import com.nest.app.curriculum.service.CourseService;
import com.nest.common.security.FeatureKey;
import com.nest.common.security.RequiresFeature;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.UUID;

@RestController
@Tag(name = "Courses")
public class CourseController {

    private final CourseService courseService;

    public CourseController(CourseService courseService) {
        this.courseService = courseService;
    }

    @PostMapping("/courses")
    @RequiresFeature(FeatureKey.COURSE_MANAGEMENT)
    public CourseResponse create(@Valid @RequestBody CreateCourseRequest request) {
        return courseService.create(request);
    }

    /** membershipId narrows the result to just the courses that ONE membership is actually
     * mapped to (e.g. the Fees screen's "look up a student" course picker) - without it, every
     * active course in the academy is returned, same as before. */
    @GetMapping("/courses")
    public List<CourseResponse> listActive(@RequestParam(required = false) UUID membershipId) {
        if (membershipId != null) {
            return courseService.listForMembership(membershipId);
        }
        return courseService.listActiveForActiveAcademy();
    }

    /** Course-management admin view - every course in the active academy regardless of status,
     * so a deactivated course can still be found and reactivated. */
    @GetMapping("/courses/all")
    @RequiresFeature(FeatureKey.COURSE_MANAGEMENT)
    public List<CourseResponse> listAll() {
        return courseService.listAllForActiveAcademy();
    }

    @GetMapping("/courses/{id}")
    public CourseResponse get(@PathVariable UUID id) {
        return courseService.get(id);
    }

    @PutMapping("/courses/{id}")
    @RequiresFeature(FeatureKey.COURSE_MANAGEMENT)
    public CourseResponse update(@PathVariable UUID id, @Valid @RequestBody UpdateCourseRequest request) {
        return courseService.update(id, request);
    }

    @PatchMapping("/courses/{id}/status")
    @RequiresFeature(FeatureKey.COURSE_MANAGEMENT)
    public CourseResponse setStatus(@PathVariable UUID id, @RequestParam CourseStatus status) {
        return courseService.setStatus(id, status);
    }
}
