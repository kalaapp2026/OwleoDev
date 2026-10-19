package com.nest.app.academy.service;

import com.nest.app.academy.dto.AcademySettingsDtos.ExportResponse;
import com.nest.app.academy.entity.AcademyExport;
import com.nest.app.academy.repository.AcademyExportRepository;
import com.nest.app.attendance.entity.Attendance;
import com.nest.app.attendance.repository.AttendanceRepository;
import com.nest.app.curriculum.entity.Course;
import com.nest.app.curriculum.repository.CourseRepository;
import com.nest.app.enrolment.entity.Batch;
import com.nest.app.enrolment.repository.BatchRepository;
import com.nest.app.fees.entity.FeeTransaction;
import com.nest.app.fees.repository.FeeTransactionRepository;
import com.nest.app.identity.entity.AcademyMembership;
import com.nest.app.identity.entity.CourseMap;
import com.nest.app.identity.entity.User;
import com.nest.app.identity.repository.AcademyMembershipRepository;
import com.nest.app.identity.repository.CourseMapRepository;
import com.nest.app.identity.repository.UserRepository;
import com.nest.app.scheduling.entity.ClassInstance;
import com.nest.app.scheduling.repository.ClassInstanceRepository;
import com.nest.common.audit.Auditable;
import com.nest.common.exception.BadRequestException;
import com.nest.common.exception.ForbiddenException;
import com.nest.common.security.MembershipClaim;
import com.nest.common.security.Role;
import com.nest.common.security.TenantContext;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.nio.charset.StandardCharsets;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;

/**
 * CSV exports of the academy's own data for its Academy Admin: students, the fees ledger, and
 * attendance. Every query is scoped to the caller's academy - the ledger by its own academy_id
 * column, the rest by walking from the academy's courses and memberships - and nothing here takes
 * an id from the request.
 *
 * <p>The files open straight in Excel: a UTF-8 byte-order mark so Indic names survive, and any text
 * cell that begins with a formula character is prefixed so a hostile name such as {@code =cmd()}
 * is read as text, not run.
 */
@Service
public class AcademyExportService {

    public static final String STUDENTS = "students";
    public static final String FEES = "fees";
    public static final String ATTENDANCE = "attendance";

    /** Attendance is exported for the last year - the whole history of a long-running academy is
     * rarely what is wanted, and an unbounded export is how a request takes the server down. */
    private static final int ATTENDANCE_DAYS = 365;

    public record ExportFile(String fileName, byte[] bytes, int rows) {
    }

    private final AcademyExportRepository exportRepository;
    private final AcademyMembershipRepository membershipRepository;
    private final UserRepository userRepository;
    private final CourseRepository courseRepository;
    private final CourseMapRepository courseMapRepository;
    private final FeeTransactionRepository feeTransactionRepository;
    private final BatchRepository batchRepository;
    private final ClassInstanceRepository classInstanceRepository;
    private final AttendanceRepository attendanceRepository;

    public AcademyExportService(AcademyExportRepository exportRepository, AcademyMembershipRepository membershipRepository,
                                UserRepository userRepository, CourseRepository courseRepository,
                                CourseMapRepository courseMapRepository, FeeTransactionRepository feeTransactionRepository,
                                BatchRepository batchRepository, ClassInstanceRepository classInstanceRepository,
                                AttendanceRepository attendanceRepository) {
        this.exportRepository = exportRepository;
        this.membershipRepository = membershipRepository;
        this.userRepository = userRepository;
        this.courseRepository = courseRepository;
        this.courseMapRepository = courseMapRepository;
        this.feeTransactionRepository = feeTransactionRepository;
        this.batchRepository = batchRepository;
        this.classInstanceRepository = classInstanceRepository;
        this.attendanceRepository = attendanceRepository;
    }

    @Transactional
    @Auditable(action = "ACADEMY_DATA_EXPORTED", entityType = "academy_export")
    public ExportFile export(String kind) {
        MembershipClaim membership = TenantContext.currentMembership();
        if (membership.roleType() != Role.ACADEMY_ADMIN) {
            throw new ForbiddenException("Only the Academy Admin can export academy data.");
        }
        UUID academyId = membership.academyId();
        LocalDate today = LocalDate.now();
        ExportFile file = switch (kind) {
            case STUDENTS -> students(academyId, today);
            case FEES -> fees(academyId, today);
            case ATTENDANCE -> attendance(academyId, today);
            default -> throw new BadRequestException("Unknown export: " + kind);
        };
        exportRepository.save(AcademyExport.builder()
                .academyId(academyId).kind(kind).fileName(file.fileName()).rowCount(file.rows())
                .sizeBytes(file.bytes().length).createdBy(TenantContext.currentUserId()).build());
        return file;
    }

    @Transactional(readOnly = true)
    public List<ExportResponse> recent() {
        MembershipClaim membership = TenantContext.currentMembership();
        if (membership.roleType() != Role.ACADEMY_ADMIN) {
            throw new ForbiddenException("Only the Academy Admin can export academy data.");
        }
        return exportRepository.findTop10ByAcademyIdOrderByCreatedAtDesc(membership.academyId()).stream()
                .map(e -> new ExportResponse(e.getId(), e.getKind(), e.getFileName(), e.getRowCount(), e.getSizeBytes(), e.getCreatedAt()))
                .toList();
    }

    // ---- Students ----

    private ExportFile students(UUID academyId, LocalDate today) {
        List<AcademyMembership> students = membershipRepository.findByAcademyId(academyId).stream()
                .filter(m -> m.getRoleType() == Role.STUDENT).toList();
        Map<UUID, User> users = usersFor(students.stream().map(AcademyMembership::getUserId).collect(Collectors.toSet()));
        Map<UUID, String> courseNames = courseNames(academyId);
        Map<UUID, List<String>> coursesByMembership = new HashMap<>();
        if (!students.isEmpty()) {
            for (CourseMap map : courseMapRepository.findByMembershipIdIn(
                    students.stream().map(AcademyMembership::getId).collect(Collectors.toSet()))) {
                String name = courseNames.get(map.getCourseId());
                if (map.isActive() && name != null) {
                    coursesByMembership.computeIfAbsent(map.getMembershipId(), k -> new ArrayList<>()).add(name);
                }
            }
        }
        List<List<String>> rows = new ArrayList<>();
        for (AcademyMembership m : students.stream().sorted(Comparator.comparing(m -> nameOf(users.get(m.getUserId())).toLowerCase())).toList()) {
            User u = users.get(m.getUserId());
            rows.add(List.of(
                    text(nameOf(u)), text(u == null ? "" : u.getUsername()), text(u == null ? "" : u.getPhone()),
                    text(u == null ? "" : u.getEmail()), text(m.getStatus().name()),
                    text(coursesByMembership.getOrDefault(m.getId(), List.of()).stream().sorted().collect(Collectors.joining("; "))),
                    text(m.getJoiningDate() == null ? "" : m.getJoiningDate().toString())));
        }
        return build("students-" + today + ".csv", List.of("Name", "Username", "Phone", "Email", "Status", "Courses", "Joined"), rows);
    }

    // ---- Fees ledger ----

    private ExportFile fees(UUID academyId, LocalDate today) {
        List<FeeTransaction> ledger = feeTransactionRepository.findByAcademyIdAndOccurredOnBetweenOrderByOccurredOnDesc(
                academyId, LocalDate.of(2000, 1, 1), today.plusDays(1));
        Map<UUID, String> names = studentNames(ledger.stream().map(FeeTransaction::getMembershipId).collect(Collectors.toSet()));
        Map<UUID, String> courseNames = courseNames(academyId);
        List<List<String>> rows = new ArrayList<>();
        for (FeeTransaction t : ledger) {
            rows.add(List.of(
                    text(t.getOccurredOn().toString()), text(names.getOrDefault(t.getMembershipId(), "")),
                    text(courseNames.getOrDefault(t.getCourseId(), "")), text(t.getPeriod()),
                    text(t.getCategory() == null ? "" : t.getCategory().name()), text(t.getMode() == null ? "" : t.getMode().name()),
                    // A number, so it stays one: a reversal is a negative amount and must not be text-escaped.
                    t.getAmountPaid().toPlainString(),
                    text(t.isReversal() ? "Reversal" : ""), text(t.getReversalReason()), text(t.getNote()), text(t.getGatewayRef())));
        }
        return build("fees-ledger-" + today + ".csv",
                List.of("Date", "Student", "Course", "Period", "Category", "Mode", "Amount", "Reversal", "Reversal reason", "Note", "Reference"),
                rows);
    }

    // ---- Attendance ----

    private ExportFile attendance(UUID academyId, LocalDate today) {
        Map<UUID, String> courseNames = courseNames(academyId);
        List<Batch> batches = courseNames.isEmpty() ? List.of() : batchRepository.findByCourseIdIn(courseNames.keySet());
        Map<UUID, Batch> batchById = batches.stream().collect(Collectors.toMap(Batch::getId, b -> b));
        List<ClassInstance> instances = batches.isEmpty() ? List.of() : classInstanceRepository.findByBatchIdInAndDateBetween(
                batchById.keySet(), today.minusDays(ATTENDANCE_DAYS), today);
        Map<UUID, ClassInstance> instanceById = instances.stream().collect(Collectors.toMap(ClassInstance::getId, i -> i));
        List<Attendance> records = instances.isEmpty() ? List.of() : attendanceRepository.findByClassInstanceIdIn(instanceById.keySet());
        Map<UUID, String> names = studentNames(records.stream().map(Attendance::getMembershipId).collect(Collectors.toSet()));

        List<List<String>> rows = new ArrayList<>();
        records.stream()
                .sorted(Comparator.comparing((Attendance a) -> instanceById.get(a.getClassInstanceId()).getDate()).reversed())
                .forEach(a -> {
                    ClassInstance instance = instanceById.get(a.getClassInstanceId());
                    Batch batch = batchById.get(instance.getBatchId());
                    rows.add(List.of(
                            text(instance.getDate().toString()), text(courseNames.getOrDefault(batch.getCourseId(), "")),
                            text(batch.getName()), text(names.getOrDefault(a.getMembershipId(), "")), text(a.getStatus().name())));
                });
        return build("attendance-" + today + ".csv", List.of("Date", "Course", "Batch", "Student", "Status"), rows);
    }

    // ---- helpers ----

    private Map<UUID, String> courseNames(UUID academyId) {
        return courseRepository.findByAcademyIdOrderByNameAsc(academyId).stream()
                .collect(Collectors.toMap(Course::getId, Course::getName));
    }

    private Map<UUID, User> usersFor(Set<UUID> userIds) {
        return userRepository.findAllById(userIds).stream().collect(Collectors.toMap(User::getId, u -> u));
    }

    private Map<UUID, String> studentNames(Set<UUID> membershipIds) {
        if (membershipIds.isEmpty()) {
            return Map.of();
        }
        List<AcademyMembership> memberships = membershipRepository.findAllById(membershipIds);
        Map<UUID, User> users = usersFor(memberships.stream().map(AcademyMembership::getUserId).collect(Collectors.toSet()));
        Map<UUID, String> names = new HashMap<>();
        for (AcademyMembership m : memberships) {
            names.put(m.getId(), nameOf(users.get(m.getUserId())));
        }
        return names;
    }

    private static String nameOf(User u) {
        if (u == null) {
            return "";
        }
        return u.getFullName() != null && !u.getFullName().isBlank() ? u.getFullName() : u.getUsername();
    }

    /** A text cell, made safe to open in a spreadsheet and quoted for CSV. */
    private static String text(String value) {
        String v = value == null ? "" : value;
        if (!v.isEmpty() && "=+-@\t\r".indexOf(v.charAt(0)) >= 0) {
            v = "'" + v;
        }
        return "\"" + v.replace("\"", "\"\"") + "\"";
    }

    private static ExportFile build(String fileName, List<String> header, List<List<String>> rows) {
        StringBuilder csv = new StringBuilder("﻿");
        csv.append(header.stream().map(AcademyExportService::text).collect(Collectors.joining(","))).append("\r\n");
        for (List<String> row : rows) {
            csv.append(String.join(",", row)).append("\r\n");
        }
        return new ExportFile(fileName, csv.toString().getBytes(StandardCharsets.UTF_8), rows.size());
    }
}
