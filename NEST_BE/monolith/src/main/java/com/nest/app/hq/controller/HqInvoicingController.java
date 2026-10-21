package com.nest.app.hq.controller;

import com.nest.app.hq.HqAccess;
import com.nest.app.hq.HqRole;
import com.nest.app.hq.service.HqInvoicing;
import com.nest.common.exception.ForbiddenException;
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

import java.util.List;
import java.util.Map;
import java.util.UUID;

/**
 * Invoicing: the monthly bill run to academy admins. Part of the Finance workspace, so it needs that open;
 * readable by Super and Finance admins, and only they can change it.
 */
@RestController
@RequestMapping("/admin/hq/invoicing")
@Tag(name = "HQ Console")
@PreAuthorize("hasRole('SUPER_ADMIN')")
public class HqInvoicingController {

    private final HqAccess access;
    private final HqInvoicing invoicing;

    public HqInvoicingController(HqAccess access, HqInvoicing invoicing) {
        this.access = access;
        this.invoicing = invoicing;
    }

    private void read() {
        access.requireModule("invoicing");
        access.requireFinanceWorkspace();
    }

    private void write() {
        read();
        HqRole r = access.role();
        if (r != HqRole.SUPER && r != HqRole.FINANCE) throw new ForbiddenException("Only a Super admin or Finance admin can change invoicing");
    }

    @GetMapping("/next")
    public Map<String, Object> next() {
        read();
        return invoicing.next();
    }

    @PutMapping("/settings")
    public void settings(@RequestBody Map<String, Object> body) {
        write();
        invoicing.saveSettings(body);
    }

    @PutMapping("/drafts/{academyId}")
    public void saveDraft(@PathVariable UUID academyId, @RequestBody Map<String, Object> body) {
        write();
        invoicing.saveDraft(academyId, body);
    }

    @DeleteMapping("/drafts/{academyId}")
    public void resetDraft(@PathVariable UUID academyId) {
        write();
        invoicing.resetDraft(academyId);
    }

    /** Makes the next month's bills. Body: {send: true} also sends them. */
    @PostMapping("/run")
    public Map<String, Object> run(@RequestBody Map<String, Object> body) {
        write();
        return invoicing.run(Boolean.TRUE.equals(body.get("send")));
    }

    @GetMapping("/history")
    public List<Map<String, Object>> history() {
        read();
        return invoicing.history();
    }

    @GetMapping("/history/{period}")
    public List<Map<String, Object>> runBills(@PathVariable String period) {
        read();
        return invoicing.runBills(period);
    }

    @PostMapping("/history/{period}/send")
    public Map<String, Object> sendRun(@PathVariable String period) {
        write();
        return invoicing.sendRun(period);
    }

    @PostMapping("/bills/{id}/send")
    public Map<String, Object> sendOne(@PathVariable UUID id) {
        write();
        return invoicing.sendOne(id);
    }
}
