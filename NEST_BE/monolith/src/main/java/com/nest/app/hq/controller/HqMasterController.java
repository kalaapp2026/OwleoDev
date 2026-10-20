package com.nest.app.hq.controller;

import com.nest.app.hq.HqAccess;
import com.nest.app.hq.HqAudit;
import com.nest.app.hq.service.HqMaster;
import com.nest.app.hq.service.HqUsers;
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
import java.util.List;
import java.util.Map;
import java.util.UUID;

@RestController
@RequestMapping("/admin/hq/master")
@Tag(name = "HQ Console")
@PreAuthorize("hasRole('SUPER_ADMIN')")
public class HqMasterController {

    private final HqAccess access;
    private final HqMaster master;
    private final HqUsers users;
    private final HqAudit audit;

    public HqMasterController(HqAccess access, HqMaster master, HqUsers users, HqAudit audit) {
        this.access = access;
        this.master = master;
        this.users = users;
        this.audit = audit;
    }

    /** Everything the screen shows in one read: the three lists, the required fields with how many people lack each, and the history. */
    @GetMapping
    public Map<String, Object> all() {
        access.requireModule("master");
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("batches", master.items("batches"));
        out.put("roles", master.items("roles"));
        out.put("cats", master.items("cats"));
        Map<String, Integer> gaps = users.gapCounts();
        List<Map<String, Object>> fields = new java.util.ArrayList<>();
        for (var f : users.requiredFields()) {
            Map<String, Object> m = new LinkedHashMap<>(f);
            m.put("missing", gaps.getOrDefault((String) f.get("key"), 0));
            fields.add(m);
        }
        out.put("fields", fields);
        out.put("history", audit.recent("master", null, 8));
        return out;
    }

    @PostMapping("/{tab}")
    public void add(@PathVariable String tab, @RequestBody Map<String, String> body) {
        access.requireModule("master");
        access.requireSuper();
        master.add(tab, body.get("name"));
    }

    @PutMapping("/items/{id}")
    public void toggle(@PathVariable UUID id, @RequestBody Map<String, Object> body) {
        access.requireModule("master");
        access.requireSuper();
        master.setActive(id, Boolean.TRUE.equals(body.get("active")));
    }

    @PutMapping("/fields/{field}")
    public void required(@PathVariable String field, @RequestBody Map<String, Object> body) {
        access.requireModule("master");
        access.requireSuper();
        master.setRequired(field, Boolean.TRUE.equals(body.get("required")));
    }
}
