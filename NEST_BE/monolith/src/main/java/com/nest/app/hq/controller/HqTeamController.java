package com.nest.app.hq.controller;

import com.nest.app.hq.HqAccess;
import com.nest.app.hq.service.HqPlatform;
import com.nest.app.hq.service.HqTeam;
import com.nest.app.hq.service.HqWorkspace;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;
import java.util.UUID;

/** Platform settings (app mode), the HQ team, and the dashboard's Platform status tab. */
@RestController
@RequestMapping("/admin/hq")
@Tag(name = "HQ Console")
@PreAuthorize("hasRole('SUPER_ADMIN')")
public class HqTeamController {

    private final HqAccess access;
    private final HqTeam team;
    private final HqPlatform platform;
    private final HqWorkspace workspace;

    public HqTeamController(HqAccess access, HqTeam team, HqPlatform platform, HqWorkspace workspace) {
        this.access = access;
        this.team = team;
        this.platform = platform;
        this.workspace = workspace;
    }

    /** Whether the Finance workspace is open for the signed-in person. */
    @GetMapping("/workspace")
    public Map<String, Object> workspace() {
        return workspace.status();
    }

    @PostMapping("/workspace/finance/code")
    public Map<String, String> workspaceCode() {
        access.requireModule("finance");
        return workspace.sendCode();
    }

    @PostMapping("/workspace/finance/open")
    public void workspaceOpen(@RequestBody Map<String, String> body) {
        access.requireModule("finance");
        workspace.open(body.get("code"));
    }

    @DeleteMapping("/workspace/finance")
    public void workspaceClose() {
        workspace.close();
    }

    @GetMapping("/platform")
    public Map<String, Object> status() {
        access.requireModule("overview");
        return platform.status();
    }

    @GetMapping("/settings")
    public Map<String, Object> settings() {
        access.requireModule("settings");
        return platform.appMode();
    }

    @PutMapping("/settings/app-mode")
    public void appMode(@RequestBody Map<String, String> body) {
        access.requireModule("settings");
        platform.setAppMode(body.get("mode"));
    }

    @GetMapping("/team")
    public Map<String, Object> team() {
        access.requireModule("settings");
        return team.list();
    }

    @PostMapping("/team")
    public Map<String, Object> invite(@RequestBody Map<String, String> body) {
        access.requireSuper();
        return team.invite(body.get("name"), body.get("username"), body.get("phone"), body.get("email"), body.get("role"));
    }

    @PutMapping("/team/{id}/role")
    public void role(@PathVariable UUID id, @RequestBody Map<String, String> body) {
        access.requireSuper();
        team.setRole(id, body.get("role"));
    }

    @PutMapping("/team/{id}/active")
    public void active(@PathVariable UUID id, @RequestBody Map<String, Object> body) {
        access.requireSuper();
        team.setActive(id, Boolean.TRUE.equals(body.get("active")));
    }
}
