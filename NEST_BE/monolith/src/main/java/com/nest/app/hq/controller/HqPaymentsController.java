package com.nest.app.hq.controller;

import com.nest.app.hq.HqAccess;
import com.nest.app.hq.service.HqPayments;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

/** Payments: the transaction history and the account mapping. Part of the Finance workspace. */
@RestController
@RequestMapping("/admin/hq/payments")
@Tag(name = "HQ Console")
@PreAuthorize("hasRole('SUPER_ADMIN')")
public class HqPaymentsController {

    private final HqAccess access;
    private final HqPayments payments;

    public HqPaymentsController(HqAccess access, HqPayments payments) {
        this.access = access;
        this.payments = payments;
    }

    private void read() {
        access.requireModule("payments");
        access.requireFinanceWorkspace();
    }

    @GetMapping("/transactions")
    public Map<String, Object> transactions(@RequestParam(required = false) String month, @RequestParam(required = false) String type,
                                            @RequestParam(required = false) String status, @RequestParam(required = false) String source,
                                            @RequestParam(required = false) String academy, @RequestParam(required = false) String q) {
        read();
        return payments.transactions(month, type, status, source, academy, q);
    }

    @GetMapping("/accounts")
    public Map<String, Object> accounts() {
        read();
        return payments.accounts();
    }
}
