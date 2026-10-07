package com.nest.app.selfservice.controller;

import com.nest.app.selfservice.dto.ExploreCourseResponse;
import com.nest.app.selfservice.service.StudentSelfService;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.Map;
import java.util.UUID;

/** Deliberately no @RequiresFeature anywhere: these only ever act on the caller's own membership. */
@RestController
@Tag(name = "Student self-service")
public class StudentSelfController {

    private final StudentSelfService service;

    public StudentSelfController(StudentSelfService service) {
        this.service = service;
    }

    @GetMapping("/me/courses/explore")
    public List<ExploreCourseResponse> explore() {
        return service.explore();
    }

    @PostMapping("/me/courses/{courseId}/interest")
    public ResponseEntity<Void> interested(@PathVariable UUID courseId) {
        service.markInterested(courseId);
        return ResponseEntity.noContent().build();
    }

    @DeleteMapping("/me/courses/{courseId}/interest")
    public ResponseEntity<Void> withdraw(@PathVariable UUID courseId) {
        service.withdrawInterest(courseId);
        return ResponseEntity.noContent().build();
    }

    @PostMapping("/me/deletion-request")
    public Map<String, Boolean> requestDeletion() {
        return Map.of("created", service.requestDeletion());
    }

    @GetMapping("/me/deletion-request")
    public Map<String, Boolean> deletionStatus() {
        return Map.of("pending", service.deletionPending());
    }
}
