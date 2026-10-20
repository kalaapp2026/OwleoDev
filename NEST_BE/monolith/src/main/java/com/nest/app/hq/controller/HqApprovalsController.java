package com.nest.app.hq.controller;

import com.nest.app.hq.HqAccess;
import com.nest.app.hq.HqRole;
import com.nest.app.hq.service.HqApprovals;
import com.nest.common.exception.ForbiddenException;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.LinkedHashMap;
import java.util.Map;
import java.util.UUID;

/** Approvals: the requests waiting for an HQ decision and the workflows that decide them. */
@RestController
@RequestMapping("/admin/hq/approvals")
@Tag(name = "HQ Console")
@PreAuthorize("hasRole('SUPER_ADMIN')")
public class HqApprovalsController {

    private final HqAccess access;
    private final HqApprovals approvals;

    public HqApprovalsController(HqAccess access, HqApprovals approvals) {
        this.access = access;
        this.approvals = approvals;
    }

    @GetMapping
    public Map<String, Object> all() {
        access.requireModule("approvals");
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("requests", approvals.list());
        out.put("workflows", approvals.workflows());
        out.put("counts", approvals.counts());
        out.put("isSuper", access.role() == HqRole.SUPER);
        return out;
    }

    /** approve, return or reject. Whether this person may act at the request's current stage is checked inside. */
    @PostMapping("/{id}/decide")
    public void decide(@PathVariable UUID id, @RequestBody Map<String, String> body) {
        access.requireModule("approvals");
        String action = body.getOrDefault("action", "");
        if (!java.util.List.of("approve", "return", "reject").contains(action)) {
            throw new com.nest.common.exception.BadRequestException("Choose approve, return or reject.");
        }
        approvals.decide(id, action, body.get("comment"));
    }

    @PutMapping("/{id}/plan")
    public void choosePlan(@PathVariable UUID id, @RequestBody Map<String, String> body) {
        access.requireModule("approvals");
        approvals.choosePlan(id, body.get("planCode"));
    }

    @PostMapping("/direct-plan")
    public void directPlan(@RequestBody Map<String, String> body) {
        HqRole r = access.role();
        if (r != HqRole.SUPER && r != HqRole.FINANCE) throw new ForbiddenException("Only a Super admin or Finance admin can change a plan");
        approvals.directPlanChange(UUID.fromString(body.get("academyId")), body.get("planCode"), body.get("reason"));
    }

    @PutMapping("/workflows/{type}")
    public void workflow(@PathVariable String type, @RequestBody Map<String, Object> body) {
        access.requireModule("approvals");
        approvals.saveWorkflow(type,
                body.get("slaDays") == null ? null : Integer.valueOf(body.get("slaDays").toString()),
                body.get("locked") == null ? null : Boolean.valueOf(body.get("locked").toString()));
    }
}
