package com.nest.app.identity.entity;

import com.nest.common.crypto.EncryptedStringConverter;
import com.nest.common.security.Role;
import jakarta.persistence.Column;
import jakarta.persistence.Convert;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;
import org.hibernate.annotations.CreationTimestamp;
import org.hibernate.annotations.UpdateTimestamp;

import java.time.Instant;
import java.time.LocalDate;
import java.util.UUID;

/**
 * One row per human across the whole platform (PRD 4.4) - exactly one, regardless of how many
 * academies they later join as a Student (see academy_memberships / Section 7).
 */
@Entity
@Table(name = "users")
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class User {

    @Id
    @GeneratedValue
    private UUID id;

    @Column(nullable = false, unique = true)
    private String username;

    @Column(name = "full_name", nullable = false)
    private String fullName;

    /** Encrypted at rest (PRD 4.6) - not directly queryable or unique-constrainable since the
     * encryptor uses a random IV per call. Use {@link #phoneHash} for lookups/uniqueness. */
    @Convert(converter = EncryptedStringConverter.class)
    @Column(nullable = false, length = 512)
    private String phone;

    /** Deterministic HMAC of the raw phone number (see {@link com.nest.common.crypto.PiiHasher}) -
     * used for phone-based login lookup only. NOT unique: a parent may register two children under
     * the same phone number (PRD 7.4 addendum) - {@link #email} is the platform-wide identity key. */
    @Column(name = "phone_hash", nullable = false, length = 64)
    private String phoneHash;

    /** The platform-wide dedup key (case-insensitive, partial-unique - see V11 migration; null is
     * allowed and never collides). Duplicate-email registration triggers the multi-academy
     * membership-confirmation flow instead of creating a second account. */
    private String email;

    @Convert(converter = EncryptedStringConverter.class)
    @Column(name = "dob", length = 512)
    private String dobEncrypted;

    @Convert(converter = EncryptedStringConverter.class)
    @Column(length = 1024)
    private String address;

    private String city;
    private String state;

    /** Trainer-specific; null for every other role - lives on the shared table anyway (same
     * pattern as dob/address/city/state, which are Student-specific and equally optional here). */
    @Column(name = "years_of_experience")
    private Integer yearsOfExperience;

    /** Relative URL under the static upload serving path (e.g. "/uploads/profile-images/xyz.jpg") -
     * null means no photo was ever uploaded, in which case the UI falls back to the first letter
     * of {@link #fullName}. */
    @Column(name = "profile_image_url")
    private String profileImageUrl;

    /** How this person entered the platform: SUPER_ADMIN / ARTIST / GUEST, or an ERP role if
     * created directly by an Academy Admin. Per-academy ERP role lives on {@link AcademyMembership}. */
    @Enumerated(EnumType.STRING)
    @Column(name = "role_type", nullable = false)
    private Role role;

    /** Null for OTP-only accounts (Students/Guests/Artists) - only Admin/Trainer accounts get a password (PRD 3.2/3.5). */
    @Column(name = "password_hash")
    private String passwordHash;

    @Column(name = "is_temporary_password", nullable = false)
    @Builder.Default
    private boolean temporaryPassword = false;

    @Enumerated(EnumType.STRING)
    @Column(name = "theme_preference", nullable = false)
    @Builder.Default
    private ThemePreference themePreference = ThemePreference.SYSTEM;

    @Column(nullable = false)
    @Builder.Default
    private String status = "ACTIVE";

    @CreationTimestamp
    @Column(name = "created_at", updatable = false)
    private Instant createdAt;

    @UpdateTimestamp
    @Column(name = "updated_at")
    private Instant updatedAt;

    /** Last authenticated request from this person, stamped (throttled) by ActivityTrackingFilter.
     * Deliberately NOT login time: someone who stays logged in for weeks should still only count
     * as active on the days they actually opened the app. Backs the Super Admin console's
     * active-now / DAU / WAU / MAU figures. */
    @Column(name = "last_seen_at")
    private Instant lastSeenAt;

    public LocalDate getDob() {
        return dobEncrypted == null ? null : LocalDate.parse(dobEncrypted);
    }

    public void setDob(LocalDate dob) {
        this.dobEncrypted = dob == null ? null : dob.toString();
    }
}
