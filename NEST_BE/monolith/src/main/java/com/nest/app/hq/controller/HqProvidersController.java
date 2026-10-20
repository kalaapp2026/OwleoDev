package com.nest.app.hq.controller;

import com.nest.app.hq.HqAccess;
import com.nest.app.hq.service.HqProviders;
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

import java.math.BigDecimal;
import java.util.List;
import java.util.Map;
import java.util.UUID;

@RestController
@RequestMapping("/admin/hq/providers")
@Tag(name = "HQ Console")
@PreAuthorize("hasRole('SUPER_ADMIN')")
public class HqProvidersController {

    private final HqAccess access;
    private final HqProviders providers;

    public HqProvidersController(HqAccess access, HqProviders providers) {
        this.access = access;
        this.providers = providers;
    }

    private void read() {
        access.requireModule("providers");
    }

    private void write() {
        access.requireModule("providers");
        access.requireWrite();
    }

    private static String s(Map<String, Object> b, String k) {
        Object v = b.get(k);
        return v == null ? null : v.toString();
    }

    @GetMapping
    public Map<String, Object> overview() {
        read();
        return providers.overview();
    }

    @GetMapping("/performance")
    public Map<String, Object> performance() {
        read();
        return providers.performance();
    }

    @GetMapping("/types")
    public List<Map<String, Object>> types() {
        read();
        return providers.typeOptions();
    }

    @GetMapping("/requests")
    public List<Map<String, Object>> requests(@RequestParam(defaultValue = "open") String filter) {
        read();
        return providers.requests(filter);
    }

    @GetMapping("/{id}")
    public Map<String, Object> detail(@PathVariable UUID id) {
        read();
        return providers.detail(id);
    }

    @PostMapping
    public Map<String, Object> create(@RequestBody Map<String, Object> body) {
        write();
        return Map.of("id", providers.create(body));
    }

    @PutMapping("/{id}/links/{index}")
    public void link(@PathVariable UUID id, @PathVariable int index, @RequestBody Map<String, Object> body) {
        write();
        Object ok = body.get("ok");
        providers.setLink(id, index, ok == null ? null : Boolean.TRUE.equals(ok));
    }

    @PutMapping("/{id}/kyc/{key}")
    public void kyc(@PathVariable UUID id, @PathVariable String key, @RequestBody Map<String, Object> body) {
        write();
        providers.setKyc(id, key, Boolean.TRUE.equals(body.get("done")));
    }

    @PostMapping("/{id}/step")
    public void step(@PathVariable UUID id, @RequestBody Map<String, String> body) {
        write();
        providers.step(id, body.get("to"));
    }

    @PostMapping("/{id}/stop")
    public void stop(@PathVariable UUID id, @RequestBody Map<String, String> body) {
        write();
        providers.stop(id, body.get("kind"), body.get("reason"));
    }

    @PostMapping("/{id}/warn")
    public void warn(@PathVariable UUID id, @RequestBody Map<String, String> body) {
        write();
        providers.warn(id, body.get("message"));
    }

    @PostMapping("/types")
    public void addType(@RequestBody Map<String, String> body) {
        write();
        providers.addType(body.get("name"));
    }

    @PutMapping("/types/{code}")
    public void typeActive(@PathVariable String code, @RequestBody Map<String, Object> body) {
        write();
        providers.setTypeActive(code, Boolean.TRUE.equals(body.get("active")));
    }

    @PostMapping("/requests")
    public Map<String, Object> createRequest(@RequestBody Map<String, Object> body) {
        write();
        return Map.of("id", providers.createRequest(UUID.fromString(s(body, "academyId")), s(body, "type"), s(body, "event"), s(body, "date"), s(body, "budget")));
    }

    @GetMapping("/requests/{id}/suggestions")
    public List<Map<String, Object>> suggestions(@PathVariable UUID id) {
        read();
        return providers.suggestions(id);
    }

    @PostMapping("/requests/{id}/send")
    @SuppressWarnings("unchecked")
    public void send(@PathVariable UUID id, @RequestBody Map<String, Object> body) {
        write();
        providers.send(id, ((List<String>) body.getOrDefault("providers", List.of())).stream().map(UUID::fromString).toList());
    }

    @PostMapping("/requests/{id}/quote")
    public void quote(@PathVariable UUID id, @RequestBody Map<String, Object> body) {
        write();
        providers.quote(id, UUID.fromString(s(body, "providerId")), new BigDecimal(s(body, "amount")));
    }

    @PostMapping("/requests/{id}/hire")
    public void hire(@PathVariable UUID id, @RequestBody Map<String, String> body) {
        write();
        providers.hire(id, UUID.fromString(body.get("providerId")));
    }

    @PostMapping("/requests/{id}/close")
    public void close(@PathVariable UUID id) {
        write();
        providers.closeRequest(id);
    }

    @PostMapping("/jobs/{id}/outcome")
    public void outcome(@PathVariable UUID id, @RequestBody Map<String, Object> body) {
        write();
        providers.recordOutcome(id, s(body, "status"), body.get("rating") instanceof Number n ? n.intValue() : null, Boolean.TRUE.equals(body.get("late")), Boolean.TRUE.equals(body.get("issue")));
    }
}
