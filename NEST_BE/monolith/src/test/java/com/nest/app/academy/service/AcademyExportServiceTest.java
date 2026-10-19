package com.nest.app.academy.service;

import com.nest.app.academy.entity.AcademyExport;
import com.nest.app.academy.repository.AcademyExportRepository;
import com.nest.app.attendance.repository.AttendanceRepository;
import com.nest.app.curriculum.entity.Course;
import com.nest.app.curriculum.repository.CourseRepository;
import com.nest.app.enrolment.repository.BatchRepository;
import com.nest.app.fees.entity.FeeMode;
import com.nest.app.fees.entity.FeeTransaction;
import com.nest.app.fees.repository.FeeTransactionRepository;
import com.nest.app.identity.entity.AcademyMembership;
import com.nest.app.identity.entity.MembershipStatus;
import com.nest.app.identity.entity.User;
import com.nest.app.identity.repository.AcademyMembershipRepository;
import com.nest.app.identity.repository.CourseMapRepository;
import com.nest.app.identity.repository.UserRepository;
import com.nest.app.scheduling.repository.ClassInstanceRepository;
import com.nest.common.exception.BadRequestException;
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
import java.nio.charset.StandardCharsets;
import java.time.LocalDate;
import java.util.List;
import java.util.Set;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class AcademyExportServiceTest {

    @Mock
    private AcademyExportRepository exportRepository;
    @Mock
    private AcademyMembershipRepository membershipRepository;
    @Mock
    private UserRepository userRepository;
    @Mock
    private CourseRepository courseRepository;
    @Mock
    private CourseMapRepository courseMapRepository;
    @Mock
    private FeeTransactionRepository feeTransactionRepository;
    @Mock
    private BatchRepository batchRepository;
    @Mock
    private ClassInstanceRepository classInstanceRepository;
    @Mock
    private AttendanceRepository attendanceRepository;

    private AcademyExportService service;
    private final UUID academyId = UUID.randomUUID();

    @BeforeEach
    void setUp() {
        service = new AcademyExportService(exportRepository, membershipRepository, userRepository, courseRepository,
                courseMapRepository, feeTransactionRepository, batchRepository, classInstanceRepository, attendanceRepository);
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

    private String text(AcademyExportService.ExportFile file) {
        return new String(file.bytes(), StandardCharsets.UTF_8);
    }

    @Test
    void exportsAreForTheAcademyAdminOnly() {
        actingAs(Role.TRAINER);
        assertThatThrownBy(() -> service.export("students")).isInstanceOf(ForbiddenException.class);
        assertThatThrownBy(() -> service.recent()).isInstanceOf(ForbiddenException.class);
        verify(exportRepository, never()).save(any());
    }

    @Test
    void anUnknownExportKindIsRejected() {
        assertThatThrownBy(() -> service.export("everything")).isInstanceOf(BadRequestException.class);
    }

    @Test
    void theStudentsExportListsOnlyStudentsWithTheirCoursesAndLogsTheDownload() {
        UUID studentMembership = UUID.randomUUID();
        UUID studentUser = UUID.randomUUID();
        UUID trainerMembership = UUID.randomUUID();
        UUID courseId = UUID.randomUUID();
        when(membershipRepository.findByAcademyId(academyId)).thenReturn(List.of(
                AcademyMembership.builder().id(studentMembership).userId(studentUser).academyId(academyId)
                        .roleType(Role.STUDENT).status(MembershipStatus.ACTIVE).build(),
                AcademyMembership.builder().id(trainerMembership).userId(UUID.randomUUID()).academyId(academyId)
                        .roleType(Role.TRAINER).status(MembershipStatus.ACTIVE).build()));
        when(userRepository.findAllById(Set.of(studentUser))).thenReturn(List.of(
                User.builder().id(studentUser).username("kavya").fullName("Kavya Reddy").email("k@x.in").build()));
        when(courseRepository.findByAcademyIdOrderByNameAsc(academyId)).thenReturn(List.of(
                Course.builder().id(courseId).academyId(academyId).name("Bharatnatyam").build()));
        when(courseMapRepository.findByMembershipIdIn(Set.of(studentMembership))).thenReturn(List.of(
                com.nest.app.identity.entity.CourseMap.builder().membershipId(studentMembership).courseId(courseId).build()));

        var file = service.export("students");

        String csv = text(file);
        assertThat(file.rows()).isEqualTo(1);
        assertThat(csv).startsWith("﻿\"Name\"");
        assertThat(csv).contains("\"Kavya Reddy\"", "\"Bharatnatyam\"").doesNotContain("Trainer");
        assertThat(file.fileName()).startsWith("students-").endsWith(".csv");
        verify(exportRepository).save(any(AcademyExport.class));
    }

    @Test
    void aTextCellStartingWithAFormulaCharacterIsDefused() {
        UUID membershipId = UUID.randomUUID();
        UUID userId = UUID.randomUUID();
        when(membershipRepository.findByAcademyId(academyId)).thenReturn(List.of(
                AcademyMembership.builder().id(membershipId).userId(userId).academyId(academyId)
                        .roleType(Role.STUDENT).status(MembershipStatus.ACTIVE).build()));
        when(userRepository.findAllById(Set.of(userId))).thenReturn(List.of(
                User.builder().id(userId).username("x").fullName("=HYPERLINK(\"http://evil\")").build()));
        when(courseRepository.findByAcademyIdOrderByNameAsc(academyId)).thenReturn(List.of());
        when(courseMapRepository.findByMembershipIdIn(any())).thenReturn(List.of());

        String csv = text(service.export("students"));

        assertThat(csv).contains("\"'=HYPERLINK(\"\"http://evil\"\")\"").doesNotContain(",\"=HYPERLINK").doesNotContain("\n\"=HYPERLINK");
    }

    @Test
    void theFeesLedgerKeepsReversalsAsNegativeNumbers() {
        UUID membershipId = UUID.randomUUID();
        UUID userId = UUID.randomUUID();
        UUID courseId = UUID.randomUUID();
        when(feeTransactionRepository.findByAcademyIdAndOccurredOnBetweenOrderByOccurredOnDesc(eq(academyId), any(), any()))
                .thenReturn(List.of(
                        FeeTransaction.builder().membershipId(membershipId).courseId(courseId).academyId(academyId).period("2026-09")
                                .amountPaid(new BigDecimal("-1500.00")).mode(FeeMode.CASH).occurredOn(LocalDate.of(2026, 9, 5))
                                .reversalOfTransactionId(UUID.randomUUID()).reversalReason("Entered twice").build()));
        when(membershipRepository.findAllById(Set.of(membershipId))).thenReturn(List.of(
                AcademyMembership.builder().id(membershipId).userId(userId).academyId(academyId).roleType(Role.STUDENT).build()));
        when(userRepository.findAllById(Set.of(userId))).thenReturn(List.of(User.builder().id(userId).username("a").fullName("Aarav").build()));
        when(courseRepository.findByAcademyIdOrderByNameAsc(academyId)).thenReturn(List.of(
                Course.builder().id(courseId).academyId(academyId).name("Guitar").build()));

        String csv = text(service.export("fees"));

        assertThat(csv).contains(",-1500.00,\"Reversal\",\"Entered twice\"");
        assertThat(csv).contains("\"Aarav\"", "\"Guitar\"");
    }
}
