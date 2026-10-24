package com.nest.app.validation;

import com.google.i18n.phonenumbers.NumberParseException;
import com.google.i18n.phonenumbers.PhoneNumberUtil;
import com.google.i18n.phonenumbers.PhoneNumberUtil.PhoneNumberType;
import com.google.i18n.phonenumbers.Phonenumber.PhoneNumber;
import jakarta.validation.ConstraintValidator;
import jakarta.validation.ConstraintValidatorContext;

import java.util.regex.Pattern;

/**
 * The field rules, in one place. The app's forms apply the same rules before anything is sent
 * (see {@code core/validation} in NEST_FE), so a value the app accepts is a value the server
 * accepts - and one that arrives from anywhere else (an old build, a script) is held to them too.
 *
 * <p>Every rule treats {@code null} and blank as valid: whether a field is <em>required</em> is the
 * job of {@code @NotBlank} beside it, so one annotation stays one question.
 */
public final class FieldRules {

    private FieldRules() {
    }

    // ---- phone ----

    private static final PhoneNumberUtil PHONE = PhoneNumberUtil.getInstance();

    /** Numbers written without a country code are taken as Indian, which is what records created
     *  before the app asked for a code mean. */
    static final String DEFAULT_REGION = "IN";

    /**
     * Whether {@code value} is a real phone number in the country its calling code names (or India
     * when there is none). With {@code mobileOnly}, a number that is certainly a landline is refused:
     * these are the numbers an OTP or a WhatsApp message goes to.
     */
    public static boolean isValidPhone(String value, boolean mobileOnly) {
        if (value == null || value.isBlank()) {
            return true;
        }
        try {
            PhoneNumber number = PHONE.parse(value.trim(), DEFAULT_REGION);
            if (!PHONE.isValidNumber(number)) {
                return false;
            }
            if (!mobileOnly) {
                return true;
            }
            PhoneNumberType type = PHONE.getNumberType(number);
            return type == PhoneNumberType.MOBILE || type == PhoneNumberType.FIXED_LINE_OR_MOBILE;
        } catch (NumberParseException e) {
            return false;
        }
    }

    // ---- names and identifiers ----

    /** Letters of any script and combining marks, with spaces between them. No digits or symbols. */
    private static final Pattern PERSON_NAME = Pattern.compile("^\\p{L}[\\p{L}\\p{M} ]*$");
    private static final Pattern LETTER = Pattern.compile("\\p{L}");

    public static boolean isPersonName(String value) {
        if (value == null || value.isBlank()) {
            return true;
        }
        String name = value.trim().replaceAll("\\s+", " ");
        if (name.length() > 60 || !PERSON_NAME.matcher(name).matches()) {
            return false;
        }
        return LETTER.matcher(name).results().count() >= 2;
    }

    /** 3-30 characters: letters, digits and . _ -, starting and ending with a letter or digit. */
    private static final Pattern USERNAME = Pattern.compile("^[A-Za-z0-9](?:[A-Za-z0-9._-]{1,28}[A-Za-z0-9])?$");

    public static boolean isUsername(String value) {
        if (value == null || value.isBlank()) {
            return true;
        }
        String v = value.trim();
        // The pattern alone would let a single character through (its optional tail), so the length
        // is stated outright.
        return v.length() >= 3 && v.length() <= 30 && USERNAME.matcher(v).matches();
    }

    /**
     * The HTML living-standard address grammar plus the length limits and a top-level domain of at
     * least two letters. Strict enough to refuse {@code a@b} and {@code a@@b.com}; the real proof an
     * address works is the code emailed to it.
     */
    private static final Pattern EMAIL = Pattern.compile(
            "^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?"
                    + "(?:\\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)*\\.[A-Za-z]{2,24}$");

    public static boolean isEmail(String value) {
        if (value == null || value.isBlank()) {
            return true;
        }
        String v = value.trim();
        int at = v.indexOf('@');
        String local = at < 0 ? v : v.substring(0, at);
        return v.length() <= 254
                && local.length() <= 64
                && !local.startsWith(".")
                && !local.endsWith(".")
                && !local.contains("..")
                && EMAIL.matcher(v).matches();
    }

    /** At least 8 characters with a letter and a digit, no leading or trailing space, at most 72
     *  (the longest password bcrypt reads). */
    public static boolean isStrongPassword(String value) {
        if (value == null || value.isEmpty()) {
            return true;
        }
        return value.length() >= 8
                && value.length() <= 72
                && value.equals(value.trim())
                && LETTER.matcher(value).find()
                && value.chars().anyMatch(Character::isDigit);
    }

    /** A postal code anywhere: 3-10 letters, digits, spaces or hyphens. India's six-digit PIN fits. */
    private static final Pattern POSTAL = Pattern.compile("^[A-Za-z0-9][A-Za-z0-9 -]{1,8}[A-Za-z0-9]$");

    public static boolean isPostalCode(String value) {
        return value == null || value.isBlank() || POSTAL.matcher(value.trim()).matches();
    }

    // ---- constraint validators ----

    public static class PhoneValidator implements ConstraintValidator<Phone, String> {
        private boolean mobileOnly;

        @Override
        public void initialize(Phone annotation) {
            this.mobileOnly = annotation.mobileOnly();
        }

        @Override
        public boolean isValid(String value, ConstraintValidatorContext context) {
            return isValidPhone(value, mobileOnly);
        }
    }

    public static class PersonNameValidator implements ConstraintValidator<PersonName, String> {
        @Override
        public boolean isValid(String value, ConstraintValidatorContext context) {
            return isPersonName(value);
        }
    }

    public static class UsernameValidator implements ConstraintValidator<Username, String> {
        @Override
        public boolean isValid(String value, ConstraintValidatorContext context) {
            return isUsername(value);
        }
    }

    public static class EmailValidator implements ConstraintValidator<StrictEmail, String> {
        @Override
        public boolean isValid(String value, ConstraintValidatorContext context) {
            return isEmail(value);
        }
    }

    public static class PasswordValidator implements ConstraintValidator<StrongPassword, String> {
        @Override
        public boolean isValid(String value, ConstraintValidatorContext context) {
            return isStrongPassword(value);
        }
    }

    public static class PostalCodeValidator implements ConstraintValidator<PostalCode, String> {
        @Override
        public boolean isValid(String value, ConstraintValidatorContext context) {
            return isPostalCode(value);
        }
    }
}
