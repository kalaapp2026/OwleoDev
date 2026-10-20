package com.nest.app.hq.controller;

import com.nest.app.hq.HqAccess;
import com.nest.app.hq.service.HqSocial;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;
import java.util.UUID;

/** The Social side of the console. Every HQ role can look; posting and removing are for Super and Operations. */
@RestController
@RequestMapping("/admin/hq/social")
@Tag(name = "HQ Console")
@PreAuthorize("hasRole('SUPER_ADMIN')")
public class HqSocialController {

    private final HqAccess access;
    private final HqSocial social;

    public HqSocialController(HqAccess access, HqSocial social) {
        this.access = access;
        this.social = social;
    }

    @GetMapping("/feed")
    public Map<String, Object> feed(@RequestParam(defaultValue = "30") int limit) {
        return social.feed(Math.min(Math.max(limit, 1), 100));
    }

    @PostMapping("/posts")
    public Map<String, Object> post(@RequestBody Map<String, String> body) {
        access.requireWrite();
        return Map.of("id", social.post(body.get("text")));
    }

    @DeleteMapping("/posts/{id}")
    public void remove(@PathVariable UUID id) {
        access.requireWrite();
        social.remove(id);
    }

    @GetMapping("/search")
    public Map<String, Object> search(@RequestParam(defaultValue = "") String q, @RequestParam(defaultValue = "all") String filter) {
        return social.search(q, filter);
    }

    @GetMapping("/profile")
    public Map<String, Object> profile() {
        return social.profile();
    }
}
