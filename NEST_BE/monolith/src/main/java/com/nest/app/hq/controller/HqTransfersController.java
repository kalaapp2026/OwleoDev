package com.nest.app.hq.controller;

import com.nest.app.hq.HqAccess;
import com.nest.app.hq.service.HqTransfers;
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
@RequestMapping("/admin/hq/transfers")
@Tag(name = "HQ Console")
@PreAuthorize("hasRole('SUPER_ADMIN')")
public class HqTransfersController {

    private final HqAccess access;
    private final HqTransfers transfers;

    public HqTransfersController(HqAccess access, HqTransfers transfers) {
        this.access = access;
        this.transfers = transfers;
    }

    private void write() {
        access.requireModule("transfers");
        access.requireWrite();
    }

    @GetMapping
    public Map<String, Object> list() {
        access.requireModule("transfers");
        return transfers.list();
    }

    @PostMapping
    public Map<String, Object> create(@RequestBody Map<String, String> body) {
        write();
        String academy = body.get("academyId");
        return Map.of("id", transfers.create(academy == null || academy.isBlank() ? null : UUID.fromString(academy), body.get("name"), body.get("email"), body.get("reason"), body.get("notes")));
    }

    /** Opens the transfer for an ownership request from Approvals. */
    @PostMapping("/from-request/{requestId}")
    public Map<String, Object> fromRequest(@PathVariable UUID requestId) {
        write();
        return Map.of("id", transfers.openFromRequest(requestId));
    }

    @PostMapping("/{id}/start")
    public void start(@PathVariable UUID id, @RequestBody Map<String, String> body) {
        write();
        transfers.start(id, body.get("name"), body.get("phone"));
    }

    @PostMapping("/{id}/resend/{who}")
    public void resend(@PathVariable UUID id, @PathVariable String who) {
        write();
        transfers.resend(id, "to".equals(who) ? "to" : "from");
    }

    @PostMapping("/{id}/verify/{who}")
    public Map<String, Object> verify(@PathVariable UUID id, @PathVariable String who, @RequestBody Map<String, String> body) {
        write();
        return transfers.verify(id, "to".equals(who) ? "to" : "from", body.get("code"));
    }

    @PostMapping("/{id}/reject")
    public void reject(@PathVariable UUID id, @RequestBody Map<String, String> body) {
        write();
        transfers.reject(id, body.get("reason"));
    }
}
