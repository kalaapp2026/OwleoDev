package com.nest.app.hq.controller;

import com.nest.app.hq.HqAccess;
import com.nest.app.hq.HqRole;
import com.nest.app.hq.service.HqBilling;
import com.nest.app.hq.service.HqCatalog;
import com.nest.app.hq.service.HqCollections;
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
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.YearMonth;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.UUID;

/** Collections: what academy owners pay Owleo. Readable by Super and Finance admins; only they can change it. */
@RestController
@RequestMapping("/admin/hq/collections")
@Tag(name = "HQ Console")
@PreAuthorize("hasRole('SUPER_ADMIN')")
public class HqCollectionsController {

    private final HqAccess access;
    private final HqCollections reads;
    private final HqBilling billing;
    private final HqCatalog catalog;

    public HqCollectionsController(HqAccess access, HqCollections reads, HqBilling billing, HqCatalog catalog) {
        this.access = access;
        this.reads = reads;
        this.billing = billing;
        this.catalog = catalog;
    }

    private void read() {
        access.requireModule("collections");
        access.requireFinanceWorkspace();
    }

    private void write() {
        access.requireModule("collections");
        access.requireFinanceWorkspace();
        HqRole r = access.role();
        if (r != HqRole.SUPER && r != HqRole.FINANCE) throw new ForbiddenException("Only a Super admin or Finance admin can change collections");
    }

    @GetMapping("/overview")
    public Map<String, Object> overview(@RequestParam(required = false) String month, @RequestParam(required = false) String day) {
        read();
        return reads.overview(month, day);
    }

    @GetMapping("/bills")
    public List<Map<String, Object>> bills(@RequestParam(required = false) String period, @RequestParam(required = false) String academyId) {
        read();
        return reads.bills(period, academyId);
    }

    @GetMapping("/bills/{id}")
    public Map<String, Object> bill(@PathVariable UUID id) {
        read();
        return reads.bill(id);
    }

    @GetMapping("/academies/{id}")
    public Map<String, Object> account(@PathVariable UUID id) {
        read();
        return reads.account(id);
    }

    @PostMapping("/generate")
    public Map<String, Object> generate(@RequestParam(required = false) String period) {
        write();
        String p = period == null || period.isBlank() ? YearMonth.now().toString() : period;
        return Map.of("period", p, "created", billing.generate(p));
    }

    @PostMapping("/bills/{id}/payments")
    public void pay(@PathVariable UUID id, @RequestBody Map<String, Object> b) {
        write();
        billing.recordPayment(id, dec(b.get("amount")), str(b.get("mode")), str(b.get("reference")),
                b.get("paidOn") == null ? null : LocalDate.parse(b.get("paidOn").toString().substring(0, 10)));
    }

    @PostMapping("/bills/{id}/adjustments")
    public void adjust(@PathVariable UUID id, @RequestBody Map<String, Object> b) {
        write();
        String cat = str(b.get("category"));
        String kind = "marketing".equals(cat) ? "MARKETING" : "commission".equals(cat) ? "COMMISSION" : "ADJUSTMENT";
        billing.addCharge(id, kind, str(b.get("description")), "credit".equals(str(b.get("type"))), dec(b.get("amount")));
    }

    @PutMapping("/bills/{id}/due")
    public void due(@PathVariable UUID id, @RequestBody Map<String, Object> b) {
        write();
        billing.setDueDate(id, b.get("dueOn") == null ? null : LocalDate.parse(b.get("dueOn").toString().substring(0, 10)));
    }

    @PutMapping("/bills/{id}/offer")
    public void offer(@PathVariable UUID id, @RequestBody Map<String, Object> b) {
        write();
        billing.setOffer(id, b.get("offerId") == null ? null : UUID.fromString(b.get("offerId").toString()));
    }

    /** Reminds one academy about [invoiceIds] (or all its unpaid bills when none are named). */
    @PostMapping("/academies/{id}/remind")
    public Map<String, Object> remind(@PathVariable UUID id, @RequestBody Map<String, Object> b) {
        write();
        List<UUID> ids = ((List<?>) b.getOrDefault("invoiceIds", List.of())).stream().map(o -> UUID.fromString(o.toString())).toList();
        if (ids.isEmpty()) {
            ids = reads.bills(null, id.toString()).stream()
                    .filter(x -> ((BigDecimal) x.get("balance")).signum() > 0 && !"waived".equals(x.get("status")))
                    .map(x -> (UUID) x.get("id")).toList();
        }
        int n = billing.remind(id, ids, str(b.get("channels")), str(b.get("message")));
        return Map.of("notified", n);
    }

    /** Reminds every academy that has an overdue bill, each with its own wording. */
    @PostMapping("/remind-overdue")
    public Map<String, Object> remindOverdue(@RequestBody Map<String, Object> b) {
        write();
        var overdue = reads.bills(null, null).stream().filter(x -> "overdue".equals(x.get("status"))).toList();
        var byAcademy = overdue.stream().collect(java.util.stream.Collectors.groupingBy(x -> (UUID) x.get("academyId")));
        int academies = 0, people = 0;
        for (var e : byAcademy.entrySet()) {
            var invoices = e.getValue();
            BigDecimal total = invoices.stream().map(x -> (BigDecimal) x.get("balance")).reduce(BigDecimal.ZERO, BigDecimal::add);
            String name = String.valueOf(invoices.get(0).get("academy"));
            String msg = "Hi, this is Owleo. " + name + " has " + invoices.size() + " overdue "
                    + (invoices.size() == 1 ? "bill" : "bills") + " totalling " + HqBilling.inr(total)
                    + ". You can pay from Billing in your Owleo Nest app. Thank you!";
            people += billing.remind(e.getKey(), invoices.stream().map(x -> (UUID) x.get("id")).toList(), str(b.get("channels")), msg);
            academies++;
        }
        return Map.of("academies", academies, "notified", people);
    }

    // ---- offers ----

    @GetMapping("/offers")
    public List<Map<String, Object>> offers() {
        read();
        return catalog.offers();
    }

    @PostMapping("/offers")
    public void createOffer(@RequestBody Map<String, Object> b) {
        write();
        catalog.saveOffer(null, b);
    }

    @PutMapping("/offers/{id}")
    public void editOffer(@PathVariable UUID id, @RequestBody Map<String, Object> b) {
        write();
        catalog.saveOffer(id, b);
    }

    @PutMapping("/offers/{id}/active")
    public void offerActive(@PathVariable UUID id, @RequestBody Map<String, Object> b) {
        write();
        catalog.setOfferActive(id, Boolean.TRUE.equals(b.get("active")));
    }

    // ---- add-ons ----

    @GetMapping("/addons")
    public List<Map<String, Object>> addons() {
        read();
        return catalog.addons();
    }

    @PostMapping("/addons")
    public void createAddon(@RequestBody Map<String, Object> b) {
        write();
        catalog.saveAddon(null, b);
    }

    @PutMapping("/addons/{id}")
    public void editAddon(@PathVariable UUID id, @RequestBody Map<String, Object> b) {
        write();
        catalog.saveAddon(id, b);
    }

    @PutMapping("/addons/{id}/sale")
    public void addonSale(@PathVariable UUID id, @RequestBody Map<String, Object> b) {
        write();
        catalog.setAddonOnSale(id, Boolean.TRUE.equals(b.get("onSale")));
    }

    @PostMapping("/academies/{id}/addons")
    public void assign(@PathVariable UUID id, @RequestBody Map<String, Object> b) {
        write();
        catalog.assignAddon(id, UUID.fromString(Objects.toString(b.get("addonId"))));
    }

    @DeleteMapping("/academies/{id}/addons/{addonId}")
    public void unassign(@PathVariable UUID id, @PathVariable UUID addonId) {
        write();
        catalog.removeAddon(id, addonId);
    }

    @PutMapping("/reminder-settings")
    public void reminderSettings(@RequestBody Map<String, Object> b) {
        write();
        catalog.saveReminderSettings(b);
    }

    private static BigDecimal dec(Object o) {
        try {
            return o == null || o.toString().isBlank() ? null : new BigDecimal(o.toString().replace(",", ""));
        } catch (NumberFormatException e) {
            return null;
        }
    }

    private static String str(Object o) {
        return o == null ? "" : o.toString();
    }
}
