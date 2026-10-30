package com.nest.app.billing.controller;

import com.nest.app.billing.service.AcademyBillingService;
import com.nest.app.billing.service.SubscriptionPaymentService;
import com.nest.common.exception.ForbiddenException;
import com.nest.common.security.MembershipClaim;
import com.nest.common.security.NestPrincipal;
import com.nest.common.security.Role;
import com.nest.common.security.TenantContext;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;
import java.util.UUID;

/**
 * Billing and subscription for the signed-in Academy Admin's own academy: the plans and add-ons on offer with the
 * academy's own marked, its bills, and paying a bill online. Every call is scoped to the academy in the token.
 */
@RestController
@Tag(name = "Academy billing")
public class AcademyBillingController {

    private final AcademyBillingService billing;
    private final SubscriptionPaymentService payments;

    public AcademyBillingController(AcademyBillingService billing, SubscriptionPaymentService payments) {
        this.billing = billing;
        this.payments = payments;
    }

    @GetMapping("/academies/me/billing")
    public Map<String, Object> overview() {
        requireAdmin();
        return billing.overview();
    }

    /** Opens a checkout for the whole balance of one bill. The amount is never sent by the client. */
    @PostMapping("/academies/me/billing/invoices/{invoiceId}/pay/order")
    public Map<String, Object> order(@PathVariable UUID invoiceId) {
        requireAdmin();
        return payments.createOrder(invoiceId);
    }

    /** The checkout's signed result. The server checks the signature before anything is marked paid. */
    @PostMapping("/academies/me/billing/pay/verify")
    public Map<String, Object> verify(@RequestBody Map<String, String> body) {
        requireAdmin();
        return payments.confirm(body.get("orderId"), body.get("paymentId"), body.get("signature"));
    }

    private static void requireAdmin() {
        NestPrincipal principal = TenantContext.require();
        MembershipClaim membership = principal.activeMembership()
                .orElseThrow(() -> new ForbiddenException("Request has no active academy membership"));
        if (membership.roleType() != Role.ACADEMY_ADMIN) {
            throw new ForbiddenException("Only the Academy Admin can view or pay the academy's bills");
        }
    }
}
