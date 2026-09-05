package com.nest.app.curriculum.service;

import com.nest.app.curriculum.dto.CourseResponse;
import com.nest.app.curriculum.dto.CreateCourseRequest;
import com.nest.app.curriculum.dto.UpdateCourseRequest;
import com.nest.app.curriculum.entity.Course;
import com.nest.app.curriculum.entity.CourseCategory;
import com.nest.app.curriculum.entity.FeeCycle;
import com.nest.app.curriculum.entity.FeeModel;
import com.nest.app.curriculum.repository.CourseRepository;
import com.nest.app.identity.repository.AcademyMembershipRepository;
import com.nest.app.identity.repository.CourseMapRepository;
import com.nest.common.exception.BadRequestException;
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
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * Covers the fields V22 added - the payment-method set (which is flattened into a single column
 * and so has real round-tripping to get wrong) and the now-editable category.
 */
@ExtendWith(MockitoExtension.class)
class CourseServiceTest {

    @Mock
    private CourseRepository courseRepository;
    @Mock
    private AcademyMembershipRepository membershipRepository;
    @Mock
    private CourseMapRepository courseMapRepository;
    @Mock
    private com.nest.app.identity.service.CourseFeatureGuard courseFeatureGuard;

    private CourseService courseService;

    private final UUID academyId = UUID.randomUUID();

    @BeforeEach
    void setUp() {
        courseService = new CourseService(courseRepository, membershipRepository, courseMapRepository, courseFeatureGuard);

        MembershipClaim claim = new MembershipClaim(
                UUID.randomUUID(), academyId, "Natyalaya", Role.ACADEMY_ADMIN, Set.of(), Set.of());
        TenantContext.set(new NestPrincipal(
                UUID.randomUUID(), "meera", Role.ACADEMY_ADMIN, List.of(claim), claim.membershipId()));
    }

    /**
     * Echoes the saved entity back so assertions read what the service actually built rather than
     * a canned response.
     *
     * <p>Called per-test rather than from {@code setUp} on purpose: the rejection test must never
     * reach a save, and stubbing one globally would hide that.
     */
    private void stubSaveEchoesEntity() {
        when(courseRepository.save(any(Course.class))).thenAnswer(inv -> inv.getArgument(0));
    }

    @AfterEach
    void tearDown() {
        TenantContext.clear();
    }

    private CreateCourseRequest createRequest(Set<String> paymentMethods, String iconKey) {
        return new CreateCourseRequest(
                CourseCategory.MUSIC, "Guitar Beginner", "Six week intro", "Beginner",
                FeeModel.FIXED, new BigDecimal("1000"), null,
                null, null, null, null, null,
                FeeCycle.MONTHLY, null, 5, 10, paymentMethods, iconKey);
    }

    @Test
    void paymentMethodsRoundTripThroughTheFlattenedColumn() {
        stubSaveEchoesEntity();
        // LinkedHashSet: the stored order is the order the fee screens offer the methods in, so
        // a HashSet here would make the assertion pass or fail on iteration order by luck.
        CourseResponse response = courseService.create(
                createRequest(new LinkedHashSet<>(List.of("CASH", "UPI")), "guitar"));

        assertThat(response.paymentMethods()).containsExactly("CASH", "UPI");
    }

    @Test
    void paymentMethodsAreUpperCasedAndDeduplicated() {
        stubSaveEchoesEntity();
        CourseResponse response = courseService.create(
                createRequest(new LinkedHashSet<>(List.of("cash", "Upi", "CASH")), "guitar"));

        assertThat(response.paymentMethods()).containsExactly("CASH", "UPI");
    }

    @Test
    void omittingPaymentMethodsFallsBackToCashRatherThanNone() {
        stubSaveEchoesEntity();
        // A course with no collectable method would be silently uncollectable, so the absent case
        // defaults rather than erroring - every academy takes cash.
        assertThat(courseService.create(createRequest(null, "guitar")).paymentMethods())
                .containsExactly("CASH");
        assertThat(courseService.create(createRequest(Set.of(), "guitar")).paymentMethods())
                .containsExactly("CASH");
    }

    @Test
    void anUnsupportedPaymentMethodIsRejectedRatherThanStored() {
        assertThatThrownBy(() -> courseService.create(createRequest(Set.of("BITCOIN"), "guitar")))
                .isInstanceOf(BadRequestException.class)
                .hasMessageContaining("BITCOIN");

        // The point of the rejection is that nothing is persisted - without this the test would
        // still pass if validation ran after the save.
        verify(courseRepository, never()).save(any(Course.class));
    }

    @Test
    void iconKeyAndDueDayArePersisted() {
        stubSaveEchoesEntity();
        CourseResponse response = courseService.create(createRequest(Set.of("CASH"), "bharatanatyam"));

        assertThat(response.iconKey()).isEqualTo("bharatanatyam");
        assertThat(response.dueDayOfMonth()).isEqualTo(10);
        assertThat(response.billingDayOfMonth()).isEqualTo(5);
    }

    @Test
    void updateCanMoveACourseToADifferentCategory() {
        stubSaveEchoesEntity();
        UUID courseId = UUID.randomUUID();
        when(courseRepository.findById(courseId)).thenReturn(Optional.of(Course.builder()
                .id(courseId).academyId(academyId).category(CourseCategory.MUSIC)
                .name("Guitar Beginner").feeModel(FeeModel.FIXED).defaultFee(new BigDecimal("1000"))
                .feeCycle(FeeCycle.MONTHLY).build()));

        CourseResponse response = courseService.update(courseId, new UpdateCourseRequest(
                CourseCategory.FINE_ARTS, "Watercolour", null, null,
                FeeModel.FIXED, new BigDecimal("850"), null,
                null, null, null, null, null,
                null, 5, 10, Set.of("CASH"), "palette"));

        assertThat(response.category()).isEqualTo(CourseCategory.FINE_ARTS);
        assertThat(response.iconKey()).isEqualTo("palette");
    }
}
