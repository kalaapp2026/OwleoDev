package com.nest.app.hq.controller;

import com.nest.app.hq.HqAccess;
import com.nest.app.hq.service.HqArtists;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;
import java.util.UUID;

@RestController
@RequestMapping("/admin/hq/artists")
@Tag(name = "HQ Console")
@PreAuthorize("hasRole('SUPER_ADMIN')")
public class HqArtistsController {

    private final HqAccess access;
    private final HqArtists artists;

    public HqArtistsController(HqAccess access, HqArtists artists) {
        this.access = access;
        this.artists = artists;
    }

    private void write() {
        access.requireModule("artists");
        access.requireWrite();
    }

    private static String s(Map<String, Object> b, String k) {
        Object v = b.get(k);
        return v == null ? null : v.toString();
    }

    @GetMapping
    public Map<String, Object> list(@RequestParam(defaultValue = "pending") String f, @RequestParam(required = false) String q) {
        access.requireModule("artists");
        return artists.list(f, q);
    }

    @GetMapping("/counts")
    public Map<String, Object> counts() {
        access.requireModule("artists");
        return artists.counts();
    }

    @GetMapping("/{id}")
    public Map<String, Object> detail(@PathVariable UUID id) {
        access.requireModule("artists");
        return artists.detail(id);
    }

    @PutMapping("/{id}/details")
    public void details(@PathVariable UUID id, @RequestBody Map<String, Object> body) {
        write();
        artists.editDetails(id, body);
    }

    @PutMapping("/{id}/checklist/{key}")
    public void check(@PathVariable UUID id, @PathVariable String key, @RequestBody Map<String, Object> body) {
        write();
        artists.setCheck(id, key, Boolean.TRUE.equals(body.get("done")));
    }

    @PutMapping("/{id}/guardian")
    public void guardian(@PathVariable UUID id, @RequestBody Map<String, Object> body) {
        write();
        artists.setGuardian(id, Boolean.TRUE.equals(body.get("done")));
    }

    @PutMapping("/{id}/profiles/{index}")
    public void profile(@PathVariable UUID id, @PathVariable int index, @RequestBody Map<String, Object> body) {
        write();
        artists.setProfile(id, index, s(body, "state"), s(body, "method"), s(body, "note"));
    }

    @PostMapping("/{id}/approve")
    public void approve(@PathVariable UUID id, @RequestBody Map<String, Object> body) {
        write();
        artists.approve(id, Boolean.TRUE.equals(body.get("post")), Boolean.TRUE.equals(body.get("events")));
    }

    @PostMapping("/{id}/reject")
    public void reject(@PathVariable UUID id, @RequestBody Map<String, Object> body) {
        write();
        artists.reject(id, s(body, "note"));
    }

    @PostMapping("/{id}/ask")
    public void ask(@PathVariable UUID id, @RequestBody Map<String, Object> body) {
        write();
        artists.askMore(id, s(body, "note"));
    }

    @PostMapping("/{id}/reopen")
    public void reopen(@PathVariable UUID id) {
        write();
        artists.reopen(id);
    }

    @PutMapping("/{id}/access/{which}")
    public void access(@PathVariable UUID id, @PathVariable String which, @RequestBody Map<String, Object> body) {
        write();
        artists.setPermission(id, which, Boolean.TRUE.equals(body.get("on")));
    }

    @PostMapping("/{id}/reports")
    public void report(@PathVariable UUID id, @RequestBody Map<String, Object> body) {
        write();
        artists.logReport(id, s(body, "by"), s(body, "role"), s(body, "category"), s(body, "details"));
    }

    @PostMapping("/{id}/reports/{reportId}/dismiss")
    public void dismiss(@PathVariable UUID id, @PathVariable UUID reportId, @RequestBody Map<String, Object> body) {
        write();
        artists.dismissReport(id, reportId, s(body, "note"));
    }

    @PostMapping("/{id}/reports/{reportId}/uphold")
    public Map<String, String> uphold(@PathVariable UUID id, @PathVariable UUID reportId, @RequestBody Map<String, Object> body) {
        write();
        return Map.of("message", artists.upholdReport(id, reportId, s(body, "note")));
    }

    @PostMapping("/{id}/suspend")
    public Map<String, String> suspend(@PathVariable UUID id, @RequestBody Map<String, Object> body) {
        write();
        return Map.of("message", artists.suspend(id, s(body, "note")));
    }

    @PostMapping("/{id}/reinstate")
    public void reinstate(@PathVariable UUID id) {
        write();
        artists.reinstate(id);
    }

    @PostMapping("/{id}/ban")
    public void ban(@PathVariable UUID id, @RequestBody Map<String, Object> body) {
        write();
        artists.ban(id, s(body, "note"));
    }
}
