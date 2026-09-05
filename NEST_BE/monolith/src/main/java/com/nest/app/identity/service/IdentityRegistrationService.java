package com.nest.app.identity.service;

import com.nest.app.identity.entity.AcademyMembership;
import com.nest.app.identity.entity.CourseFeatureGrant;
import com.nest.app.identity.entity.CourseMap;
import com.nest.app.identity.entity.FeatureGrant;
import com.nest.app.identity.entity.MembershipStatus;
import com.nest.app.identity.entity.User;
import com.nest.app.identity.repository.AcademyMembershipRepository;
import com.nest.app.identity.repository.CourseFeatureGrantRepository;
import com.nest.app.identity.repository.CourseMapRepository;
import com.nest.app.identity.repository.FeatureGrantRepository;
import com.nest.app.identity.repository.UserRepository;
import com.nest.common.crypto.PiiHasher;
import com.nest.common.exception.ConflictException;
import com.nest.common.exception.ResourceNotFoundException;
import com.nest.common.security.Role;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;

/**
 * Composable building blocks other modules use to register people, in-process (the monolith's
 * whole point - academy-admin provisioning and student/trainer registration used to be HTTP
 * calls across service boundaries; now they're plain Spring bean calls, kept as small named
 * methods so a future re-split back into separate services just swaps these calls for a client).
 */
@Service
public class IdentityRegistrationService {

    private final UserRepository userRepository;
    private final AcademyMembershipRepository membershipRepository;
    private final FeatureGrantRepository featureGrantRepository;
    private final CourseFeatureGrantRepository courseFeatureGrantRepository;
    private final CourseMapRepository courseMapRepository;
    private final PiiHasher hasher;
    private final PasswordEncoder passwordEncoder;
    private final TempPasswordGenerator tempPasswordGenerator;

    public IdentityRegistrationService(UserRepository userRepository, AcademyMembershipRepository membershipRepository,
                                        FeatureGrantRepository featureGrantRepository, CourseFeatureGrantRepository courseFeatureGrantRepository,
                                        CourseMapRepository courseMapRepository,
                                        PiiHasher hasher, PasswordEncoder passwordEncoder, TempPasswordGenerator tempPasswordGenerator) {
        this.userRepository = userRepository;
        this.membershipRepository = membershipRepository;
        this.featureGrantRepository = featureGrantRepository;
        this.courseFeatureGrantRepository = courseFeatureGrantRepository;
        this.courseMapRepository = courseMapRepository;
        this.hasher = hasher;
        this.passwordEncoder = passwordEncoder;
        this.tempPasswordGenerator = tempPasswordGenerator;
    }

    /** The multi-academy dedup key (PRD 7.4) - email, not phone, since a phone number may now be
     * shared across accounts (e.g. a parent registering two children). Case-insensitive; a blank/
     * null email means "no existing account to link to," never a match. */
    public Optional<User> findByEmail(String rawEmail) {
        if (rawEmail == null || rawEmail.isBlank()) {
            return Optional.empty();
        }
        return userRepository.findByEmailIgnoreCase(rawEmail.trim());
    }

    public Optional<AcademyMembership> findMembership(UUID userId, UUID academyId) {
        return membershipRepository.findByUserIdAndAcademyId(userId, academyId);
    }

    public List<UUID> courseIdsForMembership(UUID membershipId) {
        return courseMapRepository.findByMembershipId(membershipId).stream().map(CourseMap::getCourseId).collect(Collectors.toList());
    }

    /** Admin/Trainer/Super Admin path - the roles that log in with a password (PRD 3.2/3.5). */
    @Transactional
    public UserWithTempPassword createUserWithPassword(String username, String fullName, String phone, String email, Role role) {
        assertUsernameAndEmailAreFree(username, email);

        String tempPassword = tempPasswordGenerator.generate();
        User user = User.builder()
                .username(username)
                .fullName(fullName)
                .phone(phone)
                .phoneHash(hasher.hash(phone))
                .email(email)
                .role(role)
                .passwordHash(passwordEncoder.encode(tempPassword))
                .temporaryPassword(true)
                .build();
        return new UserWithTempPassword(userRepository.save(user), tempPassword);
    }

    /** Student/Guest path - now password-based like every other role (unified login): the account
     * gets a generated temp password to change on first login, and the full manual-entry profile
     * (dob/address/city/state) that {@link #createUserWithPassword} doesn't carry. */
    @Transactional
    public UserWithTempPassword createStudentWithPassword(String username, String fullName, String phone, String email,
                                                          LocalDate dob, String address, String city, String state, Role role) {
        assertUsernameAndEmailAreFree(username, email);

        String tempPassword = tempPasswordGenerator.generate();
        User user = User.builder()
                .username(username)
                .fullName(fullName)
                .phone(phone)
                .phoneHash(hasher.hash(phone))
                .email(email)
                .address(address)
                .city(city)
                .state(state)
                .role(role)
                .passwordHash(passwordEncoder.encode(tempPassword))
                .temporaryPassword(true)
                .build();
        user.setDob(dob);
        return new UserWithTempPassword(userRepository.save(user), tempPassword);
    }

    /** Guest self-signup (PRD 7.4 addendum) - unlike every other creation path, the person sets
     * their OWN password right away (no generated temp password to change later), since this is a
     * genuine self-service account, not one an Admin/Trainer is provisioning on someone's behalf. */
    @Transactional
    public User createGuestWithPassword(String username, String rawPassword, String fullName, String phone, String email) {
        assertUsernameAndEmailAreFree(username, email);

        User user = User.builder()
                .username(username)
                .fullName(fullName)
                .phone(phone)
                .phoneHash(hasher.hash(phone))
                .email(email)
                .role(Role.GUEST)
                .passwordHash(passwordEncoder.encode(rawPassword))
                .temporaryPassword(false)
                .build();
        return userRepository.save(user);
    }

    /** Trainer path - same shape as {@link #createStudentWithPassword} (dob/address/city/state)
     * plus yearsOfExperience, which is trainer-specific. */
    @Transactional
    public UserWithTempPassword createTrainerWithPassword(String username, String fullName, String phone, String email,
                                                          LocalDate dob, String address, String city, String state,
                                                          Integer yearsOfExperience, Role role) {
        assertUsernameAndEmailAreFree(username, email);

        String tempPassword = tempPasswordGenerator.generate();
        User user = User.builder()
                .username(username)
                .fullName(fullName)
                .phone(phone)
                .phoneHash(hasher.hash(phone))
                .email(email)
                .address(address)
                .city(city)
                .state(state)
                .yearsOfExperience(yearsOfExperience)
                .role(role)
                .passwordHash(passwordEncoder.encode(tempPassword))
                .temporaryPassword(true)
                .build();
        user.setDob(dob);
        return new UserWithTempPassword(userRepository.save(user), tempPassword);
    }

    /** Issues a fresh temp password for any user (Admin "reset password" action, forgot-password).
     * Returns the plaintext temp once so it can be handed over - only the hash is ever stored. */
    @Transactional
    public String resetPassword(UUID userId) {
        User user = userRepository.findById(userId)
                .orElseThrow(() -> new ResourceNotFoundException("User not found: " + userId));
        String tempPassword = tempPasswordGenerator.generate();
        user.setPasswordHash(passwordEncoder.encode(tempPassword));
        user.setTemporaryPassword(true);
        userRepository.save(user);
        return tempPassword;
    }

    @Transactional
    public AcademyMembership createMembership(UUID userId, UUID academyId, String academyName, Role roleType,
                                                MembershipStatus status, UUID createdBy) {
        AcademyMembership membership = AcademyMembership.builder()
                .userId(userId)
                .academyId(academyId)
                .academyName(academyName)
                .roleType(roleType)
                .status(status)
                .createdBy(createdBy)
                .build();
        return membershipRepository.save(membership);
    }

    /**
     * Applies the enrolment form's extra profile fields to a freshly created (or existing) user.
     *
     * <p>Separate from the create methods rather than another dozen parameters on them: those are
     * called from several flows that have no form behind them at all (self-signup, artist
     * application), and widening their signatures would force every caller to pass nulls.
     *
     * <p>Null-safe field by field. An edit that sends only the fields it changed must not blank
     * the rest, and a registration taken over a counter is routinely half-filled.
     */
    @Transactional
    public User applyPersonDetails(User user, com.nest.app.enrolment.dto.PersonDetails details) {
        if (details == null) {
            return user;
        }
        if (details.firstName() != null) user.setFirstName(details.firstName());
        if (details.lastName() != null) user.setLastName(details.lastName());
        if (details.gender() != null) user.setGender(details.gender());
        if (details.bloodGroup() != null) user.setBloodGroup(details.bloodGroup());
        if (details.altPhone() != null) user.setAltPhone(details.altPhone());
        if (details.photoUrl() != null) user.setPhotoUrl(details.photoUrl());

        // addressLine1 maps onto the pre-existing single-line column, which stays the first line.
        if (details.addressLine1() != null) user.setAddress(details.addressLine1());
        if (details.addressLine2() != null) user.setAddressLine2(details.addressLine2());
        if (details.landmark() != null) user.setLandmark(details.landmark());
        if (details.city() != null) user.setCity(details.city());
        if (details.district() != null) user.setDistrict(details.district());
        if (details.state() != null) user.setState(details.state());
        if (details.country() != null) user.setCountry(details.country());
        if (details.pinCode() != null) user.setPinCode(details.pinCode());

        if (details.guardianName() != null) user.setGuardianName(details.guardianName());
        if (details.emergencyContact() != null) user.setEmergencyContact(details.emergencyContact());
        if (details.qualification() != null) user.setQualification(details.qualification());

        return userRepository.save(user);
    }

    /**
     * The inverse of {@link #applyPersonDetails}: reads the extended profile back out for the edit
     * form to pre-fill. Membership-scoped fields come from the membership, so a trainer teaching at
     * two academies gets this academy's joining date and salary, not the other one's.
     */
    public com.nest.app.enrolment.dto.PersonDetails personDetailsOf(User user, AcademyMembership membership) {
        return new com.nest.app.enrolment.dto.PersonDetails(
                user.getFirstName(), user.getLastName(), user.getGender(), user.getBloodGroup(),
                user.getAltPhone(), user.getPhotoUrl(),
                user.getAddress(), user.getAddressLine2(), user.getLandmark(), user.getCity(),
                user.getDistrict(), user.getState(), user.getCountry(), user.getPinCode(),
                user.getGuardianName(), user.getEmergencyContact(), user.getQualification(),
                membership == null ? null : membership.getSalary(),
                membership == null ? null : membership.getJoiningDate());
    }

    /** Stamps the membership with when this person joined THIS academy, defaulting to today. */
    @Transactional
    public void setJoiningDate(AcademyMembership membership, java.time.LocalDate joiningDate) {
        membership.setJoiningDate(joiningDate != null ? joiningDate : java.time.LocalDate.now());
        membershipRepository.save(membership);
    }

    /**
     * Records what this academy pays this trainer. A null salary is left untouched rather than
     * cleared - the field is optional on the form, and a form submitted without it should not
     * erase a figure someone entered earlier.
     */
    @Transactional
    public void setSalary(AcademyMembership membership, java.math.BigDecimal salary) {
        if (salary == null) {
            return;
        }
        membership.setSalary(salary);
        membershipRepository.save(membership);
    }

    /** Cascading delegation (PRD 3.5) is enforced by the CALLER, which must pass a subset of its
     * own held features - this method just persists whatever set it's given. */
    @Transactional
    public void replaceFeatureGrants(UUID membershipId, Set<String> featureKeys, UUID grantedBy) {
        featureGrantRepository.deleteByMembershipId(membershipId);
        featureKeys.forEach(key -> featureGrantRepository.save(
                FeatureGrant.builder().membershipId(membershipId).featureKey(key).grantedBy(grantedBy).build()));
    }

    /** Per-course version (unified trainer model): replaces a trainer's whole feature checklist,
     * scoped course-by-course. {@code courseFeatures} maps courseId -&gt; the features granted on
     * that course (an entry with an empty set means "mapped to the course, no features"). */
    @Transactional
    public void replaceCourseFeatureGrants(UUID membershipId, Map<UUID, Set<String>> courseFeatures, UUID grantedBy) {
        courseFeatureGrantRepository.deleteByMembershipId(membershipId);
        courseFeatures.forEach((courseId, features) -> features.forEach(key ->
                courseFeatureGrantRepository.save(CourseFeatureGrant.builder()
                        .membershipId(membershipId).courseId(courseId).featureKey(key).grantedBy(grantedBy).build())));
    }

    /** @param courseFees courseId -> agreed fee (null for Trainer mappings, which have no fee concept) */
    @Transactional
    public void replaceCourseMap(UUID membershipId, Map<UUID, BigDecimal> courseFees) {
        courseMapRepository.deleteByMembershipId(membershipId);
        courseFees.forEach((courseId, fee) -> courseMapRepository.save(
                CourseMap.builder().membershipId(membershipId).courseId(courseId).agreedFee(fee).build()));
    }

    /** Edit-time reconcile that (unlike {@link #replaceCourseMap}) PRESERVES the per-course active
     * flag on courses that survive the edit: adds newly-picked courses, drops de-selected ones,
     * and just updates the agreed fee on the ones that stay. Used by trainer/student edit so
     * changing someone's courses never silently reactivates one an admin had deactivated. */
    @Transactional
    public void reconcileCourseMap(UUID membershipId, Map<UUID, BigDecimal> desired) {
        Map<UUID, CourseMap> existing = new java.util.HashMap<>();
        courseMapRepository.findByMembershipId(membershipId).forEach(cm -> existing.put(cm.getCourseId(), cm));

        // Drop courses no longer selected.
        existing.forEach((courseId, cm) -> {
            if (!desired.containsKey(courseId)) {
                courseMapRepository.delete(cm);
            }
        });
        // Add new, update fee on survivors (leaving their active flag untouched).
        desired.forEach((courseId, fee) -> {
            CourseMap cm = existing.get(courseId);
            if (cm == null) {
                courseMapRepository.save(CourseMap.builder().membershipId(membershipId).courseId(courseId).agreedFee(fee).build());
            } else {
                cm.setAgreedFee(fee);
                courseMapRepository.save(cm);
            }
        });
    }

    /** Trainer profile edit - name/phone/email/dob/address/city/state/yearsOfExperience. Phone
     * re-hashes for lookup; a changed email is re-checked for uniqueness (ignoring this same user). */
    @Transactional
    public void updateTrainerProfile(UUID userId, String fullName, String phone, String email, LocalDate dob,
                                     String address, String city, String state, Integer yearsOfExperience) {
        User user = userRepository.findById(userId)
                .orElseThrow(() -> new ResourceNotFoundException("User not found: " + userId));
        assertEmailFreeForOther(userId, email);
        user.setFullName(fullName);
        user.setPhone(phone);
        user.setPhoneHash(hasher.hash(phone));
        user.setEmail(email);
        user.setDob(dob);
        user.setAddress(address);
        user.setCity(city);
        user.setState(state);
        user.setYearsOfExperience(yearsOfExperience);
        userRepository.save(user);
    }

    /** Student profile edit - the fuller manual-entry field set. */
    @Transactional
    public void updateStudentProfile(UUID userId, String fullName, String phone, String email, LocalDate dob,
                                     String address, String city, String state) {
        User user = userRepository.findById(userId)
                .orElseThrow(() -> new ResourceNotFoundException("User not found: " + userId));
        assertEmailFreeForOther(userId, email);
        user.setFullName(fullName);
        user.setPhone(phone);
        user.setPhoneHash(hasher.hash(phone));
        user.setEmail(email);
        user.setDob(dob);
        user.setAddress(address);
        user.setCity(city);
        user.setState(state);
        userRepository.save(user);
    }

    private void assertEmailFreeForOther(UUID userId, String email) {
        if (email == null || email.isBlank()) {
            return;
        }
        userRepository.findByEmailIgnoreCase(email.trim()).ifPresent(existing -> {
            if (!existing.getId().equals(userId)) {
                throw new ConflictException("This email already has a NEST account: " + email);
            }
        });
    }

    /** Additive version of {@link #replaceCourseMap} - used when a student who's ALREADY active
     * at this academy enrols in more courses, so it must never touch courses they're already
     * mapped to (a full replace would silently drop them). */
    @Transactional
    public void addCourseMap(UUID membershipId, Map<UUID, BigDecimal> courseFees) {
        Set<UUID> existing = courseMapRepository.findByMembershipId(membershipId).stream()
                .map(CourseMap::getCourseId).collect(Collectors.toSet());
        courseFees.forEach((courseId, fee) -> {
            if (!existing.contains(courseId)) {
                courseMapRepository.save(CourseMap.builder().membershipId(membershipId).courseId(courseId).agreedFee(fee).build());
            }
        });
    }

    /** Stages courses on an already-ACTIVE membership that the registering Trainer/Admin can't
     * currently see (no course-map overlap), pending the member's own OTP confirmation. */
    @Transactional
    public void stagePendingCourseGrant(UUID membershipId, Map<UUID, BigDecimal> courseFees) {
        AcademyMembership membership = membershipRepository.findById(membershipId)
                .orElseThrow(() -> new ResourceNotFoundException("Membership not found: " + membershipId));
        membership.getPendingCourseFees().putAll(courseFees);
        membershipRepository.save(membership);
    }

    /** Completes the OTP confirmation flow for BOTH cases it covers (PRD 7.4): a brand new
     * membership (flips PENDING_CONFIRMATION -&gt; ACTIVE) and courses staged on an existing ACTIVE
     * membership via {@link #stagePendingCourseGrant} - either way, whatever's in
     * {@code pendingCourseFees} is applied and cleared. */
    @Transactional
    public AcademyMembership applyConfirmedCourseGrant(UUID membershipId) {
        AcademyMembership membership = membershipRepository.findById(membershipId)
                .orElseThrow(() -> new ResourceNotFoundException("Membership not found: " + membershipId));
        if (membership.getStatus() == MembershipStatus.PENDING_CONFIRMATION) {
            membership.setStatus(MembershipStatus.ACTIVE);
        }
        addCourseMap(membershipId, membership.getPendingCourseFees());
        membership.getPendingCourseFees().clear();
        return membershipRepository.save(membership);
    }

    private void assertUsernameAndEmailAreFree(String username, String email) {
        if (userRepository.existsByUsername(username)) {
            throw new ConflictException("Username already taken: " + username);
        }
        if (email != null && !email.isBlank() && userRepository.existsByEmailIgnoreCase(email.trim())) {
            throw new ConflictException("This email already has a NEST account: " + email);
        }
    }
}
