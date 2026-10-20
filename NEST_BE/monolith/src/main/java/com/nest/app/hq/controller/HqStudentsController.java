package com.nest.app.hq.controller;

import com.nest.app.hq.HqAccess;
import com.nest.app.hq.service.HqStudents;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;
import java.util.UUID;

@RestController
@RequestMapping("/admin/hq/students")
@Tag(name = "HQ Console")
@PreAuthorize("hasRole('SUPER_ADMIN')")
public class HqStudentsController {

    private final HqAccess access;
    private final HqStudents students;

    public HqStudentsController(HqAccess access, HqStudents students) {
        this.access = access;
        this.students = students;
    }

    @GetMapping
    public Map<String, Object> list(@RequestParam UUID academy, @RequestParam(required = false) String q, @RequestParam(defaultValue = "all") String flt,
                                    @RequestParam(defaultValue = "12") int limit, @RequestParam(defaultValue = "0") int offset) {
        access.requireModule("students");
        return students.list(academy, q, flt, Math.min(Math.max(limit, 1), 100), Math.max(offset, 0));
    }

    @GetMapping("/insights")
    public Map<String, Object> insights(@RequestParam UUID academy) {
        access.requireModule("students");
        return students.insights(academy);
    }

    @GetMapping("/{membershipId}")
    public Map<String, Object> detail(@PathVariable UUID membershipId) {
        access.requireModule("students");
        return students.detail(membershipId);
    }
}
