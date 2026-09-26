package com.nest.app.academy.controller;

import com.nest.app.academy.service.AcademyService;
import com.nest.app.billing.dto.BillingDtos;
import com.nest.app.billing.service.BillingService;
import com.nest.common.exception.ForbiddenException;
import com.nest.common.security.MembershipClaim;
import com.nest.common.security.NestPrincipal;
import com.nest.common.security.Role;
import com.nest.common.security.TenantContext;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;
import java.util.Set;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.when;

/** Covers the one piece of real logic in AcademyController.myInvoices() - who is and isn't
 * allowed to see an academy's own billing. Everything downstream (the actual invoice data) is
 * BillingService's own, already-tested territory. */
@ExtendWith(MockitoExtension.class)
class AcademyControllerTest {

    @Mock
    private AcademyService academyService;
    @Mock
    private BillingService billingService;

    private AcademyController controller;

    private final UUID academyId = UUID.randomUUID();

    @AfterEach
    void tearDown() {
        TenantContext.clear();
    }

    private void actAs(Role roleType) {
        UUID membershipId = UUID.randomUUID();
        MembershipClaim claim = new MembershipClaim(membershipId, academyId, "Kalakshetra", roleType, Set.of(), Set.of());
        TenantContext.set(new NestPrincipal(UUID.randomUUID(), "meera", roleType, List.of(claim), membershipId));
    }

    @org.junit.jupiter.api.BeforeEach
    void setUp() {
        controller = new AcademyController(academyService, billingService);
    }

    @Test
    void anAcademyAdminSeesTheirOwnAcademysInvoices() {
        actAs(Role.ACADEMY_ADMIN);
        BillingDtos.InvoiceResponse invoice = new BillingDtos.InvoiceResponse(
                UUID.randomUUID(), academyId, "Kalakshetra", "2026-09", "GROWTH",
                BigDecimal.valueOf(2499), "PAID", LocalDate.now(), LocalDate.now(), false, 0,
                null, null, null, null, null);
        when(billingService.invoicesForAcademy(academyId)).thenReturn(List.of(invoice));

        List<BillingDtos.InvoiceResponse> result = controller.myInvoices();

        assertThat(result).containsExactly(invoice);
    }

    @Test
    void aTrainerIsForbiddenFromViewingBilling() {
        actAs(Role.TRAINER);

        assertThatThrownBy(() -> controller.myInvoices()).isInstanceOf(ForbiddenException.class);
    }
}
