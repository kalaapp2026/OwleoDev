package com.nest.app.hq.controller;

import com.nest.app.hq.HqAccess;
import com.nest.app.hq.service.HqOnboarding;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;
import java.util.UUID;

@RestController
@RequestMapping("/admin/hq/onboarding")
@Tag(name = "HQ Console")
@PreAuthorize("hasRole('SUPER_ADMIN')")
public class HqOnboardingController {

    private final HqAccess access;
    private final HqOnboarding onboarding;

    public HqOnboardingController(HqAccess access, HqOnboarding onboarding) {
        this.access = access;
        this.onboarding = onboarding;
    }

    private void write() {
        access.requireModule("onboarding");
        access.requireWrite();
    }

    @GetMapping
    public Map<String, Object> pipeline() {
        access.requireModule("onboarding");
        return onboarding.pipeline();
    }

    @PostMapping("/leads")
    public Map<String, Object> create(@RequestBody Map<String, Object> body) {
        write();
        return Map.of("id", onboarding.createLead(body));
    }

    /** A pre-lead: the academy's details only, no owner or account. */
    @PostMapping("/preleads")
    public Map<String, Object> createPreLead(@RequestBody Map<String, Object> body) {
        write();
        return Map.of("id", onboarding.createPreLead(body));
    }

    /** Makes a pre-lead a lead, with the owner, plan and bank details it did not have. */
    @PostMapping("/leads/{id}/promote")
    public void promote(@PathVariable UUID id, @RequestBody Map<String, Object> body) {
        write();
        onboarding.promote(id, body);
    }

    @PostMapping("/leads/{id}/drop")
    public void drop(@PathVariable UUID id) {
        write();
        onboarding.drop(id);
    }

    @PostMapping("/leads/{id}/start-demo")
    public Map<String, Object> startDemo(@PathVariable UUID id) {
        write();
        return onboarding.startDemo(id);
    }

    @PostMapping("/leads/{id}/finish-demo")
    public void finishDemo(@PathVariable UUID id) {
        write();
        onboarding.finishDemo(id);
    }

    @PostMapping("/leads/{id}/validate")
    public void validate(@PathVariable UUID id) {
        write();
        onboarding.validate(id);
    }

    @PostMapping("/leads/{id}/verify-gateway")
    public void verifyGateway(@PathVariable UUID id) {
        write();
        onboarding.verifyGateway(id);
    }

    @PostMapping("/leads/{id}/send-for-approval")
    public void sendForApproval(@PathVariable UUID id) {
        write();
        onboarding.sendForApproval(id);
    }

    @PostMapping("/leads/{id}/go-live")
    public void goLive(@PathVariable UUID id) {
        write();
        onboarding.goLive(id);
    }
}
