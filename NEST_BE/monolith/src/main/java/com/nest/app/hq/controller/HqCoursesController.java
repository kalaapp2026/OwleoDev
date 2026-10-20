package com.nest.app.hq.controller;

import com.nest.app.hq.HqAccess;
import com.nest.app.hq.service.HqCourses;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.Map;
import java.util.UUID;

@RestController
@RequestMapping("/admin/hq/courses")
@Tag(name = "HQ Console")
@PreAuthorize("hasRole('SUPER_ADMIN')")
public class HqCoursesController {

    private final HqAccess access;
    private final HqCourses courses;

    public HqCoursesController(HqAccess access, HqCourses courses) {
        this.access = access;
        this.courses = courses;
    }

    @GetMapping
    public Map<String, Object> list(@RequestParam(required = false) UUID academy, @RequestParam(required = false) String status,
                                    @RequestParam(required = false) String issue, @RequestParam(required = false) String q) {
        access.requireModule("courses");
        return courses.list(academy, status, issue, q);
    }

    @GetMapping("/batches/{id}/trainers")
    public List<Map<String, Object>> trainers(@PathVariable UUID id) {
        access.requireModule("courses");
        return courses.trainerOptions(id);
    }

    @PostMapping("/batches/{id}/trainer")
    public void assign(@PathVariable UUID id, @RequestBody Map<String, String> body) {
        access.requireModule("courses");
        access.requireWrite();
        courses.assignTrainer(id, UUID.fromString(body.getOrDefault("membershipId", "")));
    }

    @PostMapping("/batches/{id}/schedule")
    @SuppressWarnings("unchecked")
    public void schedule(@PathVariable UUID id, @RequestBody Map<String, Object> body) {
        access.requireModule("courses");
        access.requireWrite();
        courses.setSchedule(id, (List<String>) body.get("days"), (String) body.get("start"), (String) body.get("end"));
    }

    @PostMapping("/batches/{id}/end")
    public void end(@PathVariable UUID id) {
        access.requireModule("courses");
        access.requireWrite();
        courses.end(id);
    }
}
