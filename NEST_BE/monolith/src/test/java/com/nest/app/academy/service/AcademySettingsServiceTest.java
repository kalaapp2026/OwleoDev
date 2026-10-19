package com.nest.app.academy.service;

import com.nest.app.academy.dto.AcademySettingsDtos.CreateRequest;
import com.nest.app.academy.dto.AcademySettingsDtos.ResolveRequest;
import com.nest.app.academy.entity.Academy;
import com.nest.app.academy.entity.AcademyRequest;
import com.nest.app.academy.entity.AcademyRequestStatus;
import com.nest.app.academy.entity.AcademyRequestType;
import com.nest.app.academy.repository.AcademyRepository;
import com.nest.app.academy.repository.AcademyRequestRepository;
import com.nest.app.billing.entity.BillingPlan;
import com.nest.app.billing.repository.BillingPlanRepository;
import com.nest.app.billing.service.BillingService;
import com.nest.app.identity.entity.MembershipStatus;
import com.nest.app.identity.repository.AcademyMembershipRepository;
import com.nest.app.identity.repository.UserRepository;
import com.nest.common.exception.BadRequestException;
import com.nest.common.exception.ConflictException;
import com.nest.common.exception.ForbiddenException;
import com.nest.common.security.MembershipClaim;
import com.nest.common.security.NestPrincipal;
import com.nest.common.security.Role;
import com.nest.common.security.TenantContext;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.math.BigDecimal;
import java.util.List;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class AcademySettingsServiceTest {

    @Mock
    private AcademyRepository academyRepository;
    @Mock
    private AcademyRequestRepository requestRepository;
    @Mock
    private BillingPlanRepository planRepository;
    @Mock
    private BillingService billingService;
    @Mock
    private AcademyMembershipRepository membershipRepository;
    @Mock
    private UserRepository userRepository;

    private AcademySettingsService service;
    private final UUID academyId = UUID.randomUUID();
    private final Academy academy = Academy.builder().id(academyId).name("Natyalaya").plan("GROWTH").build();

    @BeforeEach
    void setUp() {
        service = new AcademySettingsService(academyRepository, requestRepository, planRepository, billingService,
                membershipRepository, userRepository);
        lenient().when(academyRepository.findById(academyId)).thenReturn(Optional.of(academy));
        lenient().when(requestRepository.save(any(AcademyRequest.class))).thenAnswer(inv -> {
            AcademyRequest r = inv.getArgument(0);
            if (r.getId() == null) {
                r.setId(UUID.randomUUID());
            }
            return r;
        });
        lenient().when(userRepository.findAllById(any())).thenReturn(List.of());
        actingAs(Role.ACADEMY_ADMIN);
    }

    @AfterEach
    void tearDown() {
        TenantContext.clear();
    }

    private void actingAs(Role role) {
        UUID membershipId = UUID.randomUUID();
        MembershipClaim claim = new MembershipClaim(membershipId, academyId, "Natyalaya", role, Set.of(), Set.of());
        TenantContext.set(new NestPrincipal(UUID.randomUUID(), "someone", role, List.of(claim), membershipId));
    }

    private BillingPlan plan(String code, String name, int price) {
        return BillingPlan.builder().code(code).displayName(name).monthlyPrice(BigDecimal.valueOf(price)).active(true).build();
    }

    @Test
    void settingsAreForTheAcademyAdminOnly() {
        actingAs(Role.TRAINER);
        assertThatThrownBy(() -> service.settings()).isInstanceOf(ForbiddenException.class);
        assertThatThrownBy(() -> service.subscription()).isInstanceOf(ForbiddenException.class);
        assertThatThrownBy(() -> service.mine()).isInstanceOf(ForbiddenException.class);
        assertThatThrownBy(() -> service.submit(new CreateRequest(AcademyRequestType.SUPPORT, "Hi", "Help", null, null, null)))
                .isInstanceOf(ForbiddenException.class);
        verify(requestRepository, never()).save(any());
    }

    @Test
    void defaultLanguageMustBeOneOfTheAppsLanguages() {
        assertThatThrownBy(() -> service.updateDefaultLanguage("xx")).isInstanceOf(BadRequestException.class);

        var response = service.updateDefaultLanguage(" HI ");

        assertThat(response.defaultLanguage()).isEqualTo("hi");
        assertThat(academy.getDefaultLanguage()).isEqualTo("hi");
        verify(academyRepository).save(academy);
    }

    @Test
    void subscriptionReportsUsageAndTheOtherPlans() {
        when(planRepository.findById("GROWTH")).thenReturn(Optional.of(plan("GROWTH", "Growth", 2499)));
        when(planRepository.findByActiveTrueOrderByMonthlyPriceAsc()).thenReturn(List.of(plan("STARTER", "Starter", 999), plan("GROWTH", "Growth", 2499)));
        when(membershipRepository.countByAcademyIdAndRoleTypeAndStatus(academyId, Role.STUDENT, MembershipStatus.ACTIVE)).thenReturn(186L);
        when(membershipRepository.countByAcademyIdAndRoleTypeAndStatus(academyId, Role.TRAINER, MembershipStatus.ACTIVE)).thenReturn(12L);

        var response = service.subscription();

        assertThat(response.current().displayName()).isEqualTo("Growth");
        assertThat(response.students()).isEqualTo(186);
        assertThat(response.trainers()).isEqualTo(12);
        assertThat(response.plans()).hasSize(2);
    }

    @Test
    void anAcademyOnAPlanWithNoRowStillGetsACard() {
        academy.setPlan("STANDARD");
        when(planRepository.findById("STANDARD")).thenReturn(Optional.empty());
        when(planRepository.findByActiveTrueOrderByMonthlyPriceAsc()).thenReturn(List.of());

        var response = service.subscription();

        assertThat(response.current().code()).isEqualTo("STANDARD");
        assertThat(response.current().monthlyPrice()).isNull();
    }

    @Test
    void anOwnershipTransferNeedsAValidNewOwnerEmail() {
        assertThatThrownBy(() -> service.submit(new CreateRequest(AcademyRequestType.OWNERSHIP_TRANSFER, null, null, "not-an-email", null, null)))
                .isInstanceOf(BadRequestException.class);

        var response = service.submit(new CreateRequest(AcademyRequestType.OWNERSHIP_TRANSFER, null, "notes", " new@owner.in ", "Stepping down", null));

        assertThat(response.targetEmail()).isEqualTo("new@owner.in");
        assertThat(response.status()).isEqualTo(AcademyRequestStatus.PENDING);
    }

    @Test
    void aPlanChangeMustTargetADifferentActivePlan() {
        when(planRepository.findById("GROWTH")).thenReturn(Optional.of(plan("GROWTH", "Growth", 2499)));
        when(planRepository.findById("NOPE")).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.submit(new CreateRequest(AcademyRequestType.PLAN_CHANGE, null, null, null, null, "NOPE")))
                .isInstanceOf(BadRequestException.class);
        assertThatThrownBy(() -> service.submit(new CreateRequest(AcademyRequestType.PLAN_CHANGE, null, null, null, null, "GROWTH")))
                .hasMessageContaining("already on");
    }

    @Test
    void aSecondPendingRequestOfTheSameKindIsRefused() {
        when(requestRepository.existsByAcademyIdAndTypeAndStatus(academyId, AcademyRequestType.ACADEMY_CLOSURE, AcademyRequestStatus.PENDING))
                .thenReturn(true);

        assertThatThrownBy(() -> service.submit(new CreateRequest(AcademyRequestType.ACADEMY_CLOSURE, null, null, null, null, null)))
                .isInstanceOf(ConflictException.class);
        verify(requestRepository, never()).save(any());
    }

    @Test
    void supportMessagesCanBeSentRepeatedlyButNeedASubjectAndMessage() {
        assertThatThrownBy(() -> service.submit(new CreateRequest(AcademyRequestType.SUPPORT, " ", "body", null, null, null)))
                .isInstanceOf(BadRequestException.class);

        service.submit(new CreateRequest(AcademyRequestType.SUPPORT, "Fees", "Question", null, null, null));
        service.submit(new CreateRequest(AcademyRequestType.SUPPORT, "Fees again", "Another", null, null, null));

        // SUPPORT never asks whether one is already pending.
        verify(requestRepository, never()).existsByAcademyIdAndTypeAndStatus(any(), any(), any());
    }

    @Test
    void approvingAPlanChangeAppliesThePlan() {
        UUID id = UUID.randomUUID();
        AcademyRequest request = AcademyRequest.builder().id(id).academyId(academyId).requestedBy(UUID.randomUUID())
                .type(AcademyRequestType.PLAN_CHANGE).targetPlan("PRO").build();
        when(requestRepository.findById(id)).thenReturn(Optional.of(request));
        actingAs(Role.SUPER_ADMIN);

        var response = service.resolve(id, new ResolveRequest(true, "Done"));

        verify(billingService).changePlan(academyId, "PRO");
        assertThat(response.status()).isEqualTo(AcademyRequestStatus.APPROVED);
        assertThat(response.resolutionNote()).isEqualTo("Done");
    }

    @Test
    void decliningOrApprovingAnotherKindNeverChangesThePlan() {
        UUID declined = UUID.randomUUID();
        UUID transfer = UUID.randomUUID();
        when(requestRepository.findById(declined)).thenReturn(Optional.of(AcademyRequest.builder().id(declined).academyId(academyId)
                .requestedBy(UUID.randomUUID()).type(AcademyRequestType.PLAN_CHANGE).targetPlan("PRO").build()));
        when(requestRepository.findById(transfer)).thenReturn(Optional.of(AcademyRequest.builder().id(transfer).academyId(academyId)
                .requestedBy(UUID.randomUUID()).type(AcademyRequestType.OWNERSHIP_TRANSFER).build()));

        assertThat(service.resolve(declined, new ResolveRequest(false, null)).status()).isEqualTo(AcademyRequestStatus.DECLINED);
        assertThat(service.resolve(transfer, new ResolveRequest(true, null)).status()).isEqualTo(AcademyRequestStatus.APPROVED);

        verify(billingService, never()).changePlan(any(), any());
    }

    @Test
    void aRequestCanOnlyBeAnsweredOnce() {
        UUID id = UUID.randomUUID();
        when(requestRepository.findById(id)).thenReturn(Optional.of(AcademyRequest.builder().id(id).academyId(academyId)
                .requestedBy(UUID.randomUUID()).type(AcademyRequestType.SUPPORT).status(AcademyRequestStatus.APPROVED).build()));

        assertThatThrownBy(() -> service.resolve(id, new ResolveRequest(true, null))).isInstanceOf(ConflictException.class);
    }
}
