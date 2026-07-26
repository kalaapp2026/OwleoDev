package com.nest.app.curriculum.service;

import com.nest.app.curriculum.dto.CourseResponse;
import com.nest.app.curriculum.dto.CreateCourseRequest;
import com.nest.app.curriculum.dto.UpdateCourseRequest;
import com.nest.app.curriculum.entity.Course;
import com.nest.app.curriculum.entity.CourseStatus;
import com.nest.app.curriculum.entity.FeeModel;
import com.nest.app.curriculum.repository.CourseRepository;
import com.nest.app.identity.entity.AcademyMembership;
import com.nest.app.identity.repository.AcademyMembershipRepository;
import com.nest.app.identity.repository.CourseMapRepository;
import com.nest.common.audit.Auditable;
import com.nest.common.exception.BadRequestException;
import com.nest.common.exception.ForbiddenException;
import com.nest.common.exception.ResourceNotFoundException;
import com.nest.common.security.TenantContext;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.util.List;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;

/** PRD 3.3. Academy Admin only - Course Management is never delegable to Trainers. */
@Service
public class CourseService {

    private final CourseRepository courseRepository;
    private final AcademyMembershipRepository membershipRepository;
    private final CourseMapRepository courseMapRepository;

    public CourseService(CourseRepository courseRepository, AcademyMembershipRepository membershipRepository,
                          CourseMapRepository courseMapRepository) {
        this.courseRepository = courseRepository;
        this.membershipRepository = membershipRepository;
        this.courseMapRepository = courseMapRepository;
    }

    @Transactional
    @Auditable(action = "COURSE_CREATED", entityType = "course")
    public CourseResponse create(CreateCourseRequest request) {
        validateFeeModelFields(request.feeModel(), request.defaultFee(), request.feePerClass(),
                request.hybridThresholdAttendance(), request.hybridFeeBelowThresholdPercent());

        Course course = Course.builder()
                .academyId(TenantContext.currentAcademyId())
                .category(request.category())
                .name(request.name())
                .description(request.description())
                .durationLevel(request.durationLevel())
                .feeModel(request.feeModel())
                .defaultFee(request.defaultFee())
                .feePerClass(request.feePerClass())
                .hybridExpectedClassesPerPeriod(request.hybridExpectedClassesPerPeriod())
                .hybridThresholdAttendance(request.hybridThresholdAttendance())
                .hybridFeeAboveThresholdPercent(request.hybridFeeAboveThresholdPercent() != null ? request.hybridFeeAboveThresholdPercent() : 100)
                .hybridFeeBelowThresholdPercent(request.hybridFeeBelowThresholdPercent())
                .hybridMinFeeAmount(request.hybridMinFeeAmount())
                .feeCycle(request.feeCycle())
                .thumbnailUrl(request.thumbnailUrl())
                .billingDayOfMonth(request.billingDayOfMonth())
                .status(CourseStatus.ACTIVE)
                .build();
        return toResponse(courseRepository.save(course));
    }

    /** Everyone's course picker (registration forms, dashboards, batches) - active only, so a
     * deactivated course silently stops being offered without anyone needing to filter for it. */
    @Transactional(readOnly = true)
    public List<CourseResponse> listActiveForActiveAcademy() {
        return courseRepository.findByAcademyIdAndStatus(TenantContext.currentAcademyId(), CourseStatus.ACTIVE)
                .stream().map(this::toResponse).collect(Collectors.toList());
    }

    /** Course-management admin view - every course regardless of status, so Admin can see and
     * reactivate something they previously deactivated. Gated by COURSE_MANAGEMENT at the
     * controller, not filtered here. */
    @Transactional(readOnly = true)
    public List<CourseResponse> listAllForActiveAcademy() {
        return courseRepository.findByAcademyId(TenantContext.currentAcademyId())
                .stream().map(this::toResponse).collect(Collectors.toList());
    }

    @Transactional(readOnly = true)
    public CourseResponse get(UUID id) {
        return toResponse(findOrThrow(id));
    }

    /** Just the courses ONE membership is actually mapped to - e.g. the Fees screen's "look up a
     * student" course picker, so a student mapped to 1 of the academy's 2 courses doesn't appear
     * to have access to both. Scoped to the active academy so a Trainer/Admin at one academy
     * can't probe another academy's membership IDs through this endpoint. */
    @Transactional(readOnly = true)
    public List<CourseResponse> listForMembership(UUID membershipId) {
        AcademyMembership membership = membershipRepository.findById(membershipId)
                .orElseThrow(() -> new ResourceNotFoundException("Membership not found: " + membershipId));
        if (!membership.getAcademyId().equals(TenantContext.currentAcademyId())) {
            throw new ForbiddenException("That membership does not belong to the active academy");
        }
        Set<UUID> courseIds = courseMapRepository.findByMembershipId(membershipId).stream()
                .filter(cm -> cm.isActive())
                .map(cm -> cm.getCourseId()).collect(Collectors.toSet());
        return courseRepository.findAllById(courseIds).stream().map(this::toResponse).collect(Collectors.toList());
    }

    /** Does NOT retroactively change fees already agreed with existing students (PRD business rule) -
     * CourseMap.agreedFee is copied at enrolment time and is never re-derived from this value. */
    @Transactional
    @Auditable(action = "COURSE_UPDATED", entityType = "course")
    public CourseResponse update(UUID id, UpdateCourseRequest request) {
        validateFeeModelFields(request.feeModel(), request.defaultFee(), request.feePerClass(),
                request.hybridThresholdAttendance(), request.hybridFeeBelowThresholdPercent());

        Course course = findOrThrow(id);
        course.setName(request.name());
        course.setDescription(request.description());
        course.setDurationLevel(request.durationLevel());
        course.setFeeModel(request.feeModel());
        course.setDefaultFee(request.defaultFee());
        course.setFeePerClass(request.feePerClass());
        course.setHybridExpectedClassesPerPeriod(request.hybridExpectedClassesPerPeriod());
        course.setHybridThresholdAttendance(request.hybridThresholdAttendance());
        course.setHybridFeeAboveThresholdPercent(request.hybridFeeAboveThresholdPercent() != null ? request.hybridFeeAboveThresholdPercent() : 100);
        course.setHybridFeeBelowThresholdPercent(request.hybridFeeBelowThresholdPercent());
        course.setHybridMinFeeAmount(request.hybridMinFeeAmount());
        course.setThumbnailUrl(request.thumbnailUrl());
        course.setBillingDayOfMonth(request.billingDayOfMonth());
        return toResponse(courseRepository.save(course));
    }

    /** The only way to remove a course from new-enrolment visibility - hard delete is never
     * exposed, preserving fee/attendance history for anyone already enrolled. Deactivating never
     * touches AcademyMembership/CourseMap rows: students already mapped to this course keep their
     * fee/attendance history intact, it just stops being offered for new enrolment. */
    @Transactional
    @Auditable(action = "COURSE_STATUS_CHANGED", entityType = "course")
    public CourseResponse setStatus(UUID id, CourseStatus status) {
        Course course = findOrThrow(id);
        course.setStatus(status);
        return toResponse(courseRepository.save(course));
    }

    /** NEST Course Fee Calculation Spec §2 - each model needs a different subset of fields
     * populated to actually be calculable later; catching a missing one here (not at save time)
     * gives the Admin an immediate, specific validation error on the form. */
    private void validateFeeModelFields(FeeModel feeModel, BigDecimal defaultFee, BigDecimal feePerClass,
                                         Integer hybridThresholdAttendance, Integer hybridFeeBelowThresholdPercent) {
        switch (feeModel) {
            case PER_CLASS -> {
                if (feePerClass == null) {
                    throw new BadRequestException("Per-class courses require a fee per class");
                }
            }
            case FIXED -> {
                if (defaultFee == null) {
                    throw new BadRequestException("Fixed-fee courses require a default fee");
                }
            }
            case HYBRID -> {
                if (defaultFee == null) {
                    throw new BadRequestException("Hybrid courses require a base fee");
                }
                if (hybridThresholdAttendance == null) {
                    throw new BadRequestException("Hybrid courses require a threshold attendance count");
                }
                if (hybridFeeBelowThresholdPercent == null) {
                    throw new BadRequestException("Hybrid courses require a below-threshold fee percentage");
                }
            }
        }
    }

    private Course findOrThrow(UUID id) {
        return courseRepository.findById(id).orElseThrow(() -> new ResourceNotFoundException("Course not found: " + id));
    }

    private CourseResponse toResponse(Course c) {
        return new CourseResponse(c.getId(), c.getAcademyId(), c.getCategory(), c.getName(), c.getDescription(),
                c.getDurationLevel(), c.getFeeModel(), c.getDefaultFee(), c.getFeePerClass(),
                c.getHybridExpectedClassesPerPeriod(), c.getHybridThresholdAttendance(),
                c.getHybridFeeAboveThresholdPercent(), c.getHybridFeeBelowThresholdPercent(), c.getHybridMinFeeAmount(),
                c.getFeeCycle(), c.getThumbnailUrl(), c.getStatus(), c.getBillingDayOfMonth());
    }
}
