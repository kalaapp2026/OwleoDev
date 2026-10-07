package com.nest.app.selfservice.service;

import com.nest.app.curriculum.entity.Course;
import com.nest.app.curriculum.entity.CourseStatus;
import com.nest.app.curriculum.repository.CourseRepository;
import com.nest.app.identity.entity.AcademyMembership;
import com.nest.app.identity.entity.MembershipStatus;
import com.nest.app.identity.entity.User;
import com.nest.app.identity.repository.AcademyMembershipRepository;
import com.nest.app.identity.repository.CourseMapRepository;
import com.nest.app.identity.repository.UserRepository;
import com.nest.app.notification.entity.NotificationModule;
import com.nest.app.notification.entity.NotificationType;
import com.nest.app.notification.service.NotificationService;
import com.nest.app.selfservice.dto.ExploreCourseResponse;
import com.nest.app.selfservice.entity.AccountDeletionRequest;
import com.nest.app.selfservice.entity.CourseInterest;
import com.nest.app.selfservice.repository.AccountDeletionRequestRepository;
import com.nest.app.selfservice.repository.CourseInterestRepository;
import com.nest.common.exception.ForbiddenException;
import com.nest.common.exception.ResourceNotFoundException;
import com.nest.common.security.Role;
import com.nest.common.security.TenantContext;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;

/** Things a Student does for themselves that no staff permission governs: browsing the courses
 * they could join, saying they are interested, and asking to be removed. Everything here acts on
 * the CALLER's own membership - there is no membership id parameter to get wrong. */
@Service
public class StudentSelfService {

    private final CourseRepository courseRepository;
    private final CourseMapRepository courseMapRepository;
    private final CourseInterestRepository interestRepository;
    private final AccountDeletionRequestRepository deletionRepository;
    private final AcademyMembershipRepository membershipRepository;
    private final UserRepository userRepository;
    private final NotificationService notificationService;

    public StudentSelfService(CourseRepository courseRepository, CourseMapRepository courseMapRepository,
                              CourseInterestRepository interestRepository,
                              AccountDeletionRequestRepository deletionRepository,
                              AcademyMembershipRepository membershipRepository, UserRepository userRepository,
                              NotificationService notificationService) {
        this.courseRepository = courseRepository;
        this.courseMapRepository = courseMapRepository;
        this.interestRepository = interestRepository;
        this.deletionRepository = deletionRepository;
        this.membershipRepository = membershipRepository;
        this.userRepository = userRepository;
        this.notificationService = notificationService;
    }

    @Transactional(readOnly = true)
    public List<ExploreCourseResponse> explore() {
        UUID me = TenantContext.currentMembershipId();
        Set<UUID> enrolled = courseMapRepository.findByMembershipId(me).stream()
                .map(cm -> cm.getCourseId()).collect(Collectors.toSet());
        Set<UUID> interested = interestRepository.findByMembershipId(me).stream()
                .map(CourseInterest::getCourseId).collect(Collectors.toSet());
        return courseRepository
                .findByAcademyIdAndStatusOrderByNameAsc(TenantContext.currentAcademyId(), CourseStatus.ACTIVE)
                .stream()
                .filter(c -> !enrolled.contains(c.getId()))
                .map(c -> new ExploreCourseResponse(c.getId(), c.getName(), c.getCategory().name(),
                        c.getDescription(), c.getDurationLevel(), c.getIconKey(), interested.contains(c.getId())))
                .collect(Collectors.toList());
    }

    @Transactional
    public void markInterested(UUID courseId) {
        Course course = courseRepository.findById(courseId)
                .filter(c -> c.getAcademyId().equals(TenantContext.currentAcademyId()))
                .orElseThrow(() -> new ResourceNotFoundException("Course not found: " + courseId));
        UUID me = TenantContext.currentMembershipId();
        if (interestRepository.existsByCourseIdAndMembershipId(courseId, me)) return;
        interestRepository.save(CourseInterest.builder()
                .academyId(course.getAcademyId()).courseId(courseId).membershipId(me).build());

        String who = userRepository.findById(TenantContext.currentUserId()).map(User::getFullName).orElse("A student");
        notifyAdmins(course.getAcademyId(), "Course interest",
                who + " is interested in joining " + course.getName() + ".");
    }

    @Transactional
    public void withdrawInterest(UUID courseId) {
        interestRepository.deleteByCourseIdAndMembershipId(courseId, TenantContext.currentMembershipId());
    }

    @Transactional
    public boolean requestDeletion() {
        var claim = TenantContext.currentMembership();
        if (claim.roleType() != Role.STUDENT) {
            throw new ForbiddenException("Only a student can request deletion this way");
        }
        if (deletionRepository.findFirstByMembershipIdAndStatus(claim.membershipId(), "PENDING").isPresent()) {
            return false; // already asked; do not spam the admins
        }
        deletionRepository.save(AccountDeletionRequest.builder()
                .userId(TenantContext.currentUserId())
                .membershipId(claim.membershipId())
                .academyId(claim.academyId()).build());
        String who = userRepository.findById(TenantContext.currentUserId()).map(User::getFullName).orElse("A student");
        notifyAdmins(claim.academyId(), "Account deletion request",
                who + " has asked for their account to be deleted. Review and remove them from Students if approved.");
        return true;
    }

    @Transactional(readOnly = true)
    public boolean deletionPending() {
        return deletionRepository
                .findFirstByMembershipIdAndStatus(TenantContext.currentMembershipId(), "PENDING").isPresent();
    }

    private void notifyAdmins(UUID academyId, String title, String body) {
        for (AcademyMembership admin : membershipRepository.findByAcademyIdAndRoleTypeAndStatus(
                academyId, Role.ACADEMY_ADMIN, MembershipStatus.ACTIVE)) {
            notificationService.notify(admin.getUserId(), NotificationModule.ERP,
                    NotificationType.ACADEMY_BROADCAST, title, body, null);
        }
    }
}
