package com.nest.app.validation;

import com.nest.app.academy.dto.OnboardAcademyRequest;
import com.nest.app.academy.entity.AcademyCategory;
import com.nest.app.enrolment.dto.PersonDetails;
import com.nest.app.identity.dto.ChangePasswordRequest;
import com.nest.app.identity.dto.ResetPasswordRequest;
import com.nest.app.identity.dto.SignupRequest;
import jakarta.validation.ConstraintViolation;
import jakarta.validation.Validation;
import jakarta.validation.Validator;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;
import org.junit.jupiter.params.provider.ValueSource;

import java.util.Set;
import java.util.stream.Collectors;

import static org.assertj.core.api.Assertions.assertThat;

/** The server-side twins of the app's field rules (NEST_FE core/validation). */
class FieldRulesTest {

    private static Validator validator;

    @BeforeAll
    static void createValidator() {
        validator = Validation.buildDefaultValidatorFactory().getValidator();
    }

    // ---- phone ----

    @ParameterizedTest
    @ValueSource(strings = {
            "+91 9876543210", "+919876543210", "9876543210", "98765 43210", "+91 98765-43210",
            "+1 202 555 0123", "+44 7400 123456", "+44 07400 123456", "+971 50 123 4567",
            "+65 8123 4567", "+61 412 345 678", "+49 151 23456789", "+81 90 1234 5678", "+27 82 123 4567",
    })
    void acceptsRealMobileNumbersInManyCountries(String number) {
        assertThat(FieldRules.isValidPhone(number, true)).as(number).isTrue();
    }

    @ParameterizedTest
    @ValueSource(strings = {
            "123", "98765", "+91 5876543210", "+91 98765432101", "abc", "+999 123456789", "+91",
            "9876543210 ext", "+1 202 555 012",
    })
    void rejectsNumbersThatAreNotReal(String number) {
        assertThat(FieldRules.isValidPhone(number, true)).as(number).isFalse();
    }

    @Test
    void aLandlineIsAcceptedOnlyWhereAnyNumberWillDo() {
        // 11 2345 6789 is a Delhi landline.
        assertThat(FieldRules.isValidPhone("+91 1123456789", false)).isTrue();
        assertThat(FieldRules.isValidPhone("+91 1123456789", true)).isFalse();
    }

    @Test
    void blankAndNullAreLeftToNotBlank() {
        assertThat(FieldRules.isValidPhone(null, true)).isTrue();
        assertThat(FieldRules.isValidPhone("  ", true)).isTrue();
        assertThat(FieldRules.isPersonName(null)).isTrue();
        assertThat(FieldRules.isEmail("")).isTrue();
        assertThat(FieldRules.isUsername(" ")).isTrue();
        assertThat(FieldRules.isStrongPassword(null)).isTrue();
        assertThat(FieldRules.isPostalCode("")).isTrue();
    }

    // ---- names, usernames, emails, passwords, postal codes ----

    @ParameterizedTest
    @ValueSource(strings = {"Aarav", "Aarav Shah", "आरव शाह", "ஆரவ் ஷா", "José Müller"})
    void acceptsLettersAndSpaces(String name) {
        assertThat(FieldRules.isPersonName(name)).as(name).isTrue();
    }

    @ParameterizedTest
    @ValueSource(strings = {"A", "Aarav123", "Aarav@Shah", "R2D2", "12345", "-Aarav", "Aarav_Shah",
            "Shaun O'Neil", "Mary-Ann", "A. R. Rahman", "Aarav!"})
    void rejectsNamesWithDigitsOrSymbols(String name) {
        assertThat(FieldRules.isPersonName(name)).as(name).isFalse();
    }

    @Test
    void nameLengthLimit() {
        assertThat(FieldRules.isPersonName("A".repeat(60))).isTrue();
        assertThat(FieldRules.isPersonName("A".repeat(61))).isFalse();
    }

    @ParameterizedTest
    @ValueSource(strings = {"abc", "aarav.shah", "Aarav_S", "a-b-c", "user123"})
    void acceptsUsernames(String username) {
        assertThat(FieldRules.isUsername(username)).as(username).isTrue();
    }

    @ParameterizedTest
    @ValueSource(strings = {"a", "ab", ".abc", "abc.", "-abc", "has space", "ab@cd", "a/b"})
    void rejectsUsernames(String username) {
        assertThat(FieldRules.isUsername(username)).as(username).isFalse();
    }

    @ParameterizedTest
    @ValueSource(strings = {"a@b.co", "name@example.com", "first.last@sub.example.co.in", "user+tag@example.org", "o'brien@example.ie"})
    void acceptsEmails(String email) {
        assertThat(FieldRules.isEmail(email)).as(email).isTrue();
    }

    @ParameterizedTest
    @ValueSource(strings = {"plain", "a@b", "@example.com", "a@@example.com", "a b@example.com", ".a@example.com", "a..b@example.com", "a@example..com", "a@example.c"})
    void rejectsEmails(String email) {
        assertThat(FieldRules.isEmail(email)).as(email).isFalse();
    }

    @ParameterizedTest
    @CsvSource({"abcd1234,true", "Passw0rd,true", "abcdefg1,true", "abc1,false", "abcdefgh,false", "12345678,false", "' abcdefg1',false"})
    void passwordPolicy(String password, boolean ok) {
        assertThat(FieldRules.isStrongPassword(password)).as(password).isEqualTo(ok);
    }

    @Test
    void passwordCeilingIsWhatBcryptReads() {
        assertThat(FieldRules.isStrongPassword("a1".repeat(36))).isTrue();
        assertThat(FieldRules.isStrongPassword("a1".repeat(36) + "x")).isFalse();
    }

    @ParameterizedTest
    @CsvSource({"110001,true", "560001,true", "SW1A 1AA,true", "90210,true", "12,false", "!!!!!,false"})
    void postalCodes(String code, boolean ok) {
        assertThat(FieldRules.isPostalCode(code)).as(code).isEqualTo(ok);
    }

    // ---- the rules are really wired onto the request DTOs ----

    private static Set<String> invalidFields(Object dto) {
        return validator.validate(dto).stream()
                .map(ConstraintViolation::getPropertyPath)
                .map(Object::toString)
                .collect(Collectors.toSet());
    }

    private static SignupRequest signup(String username, String password, String name, String phone, String email, PersonDetails details) {
        return new SignupRequest(username, password, name, phone, email, null, details);
    }

    private static PersonDetails details(String altPhone, String pin, String emergency) {
        return new PersonDetails(null, null, null, null, altPhone, null, null, null, null, null, null, null, null, pin,
                null, emergency, null, null, null);
    }

    @Test
    void aGoodSignupPasses() {
        assertThat(invalidFields(signup("aarav.shah", "Passw0rd1", "Aarav Shah", "+91 9876543210", "aarav@example.com", null))).isEmpty();
    }

    @Test
    void aBadSignupNamesEveryProblemField() {
        assertThat(invalidFields(signup("a", "short", "Aarav123", "12345", "not-an-email", null)))
                .containsExactlyInAnyOrder("username", "password", "fullName", "phone", "email");
    }

    @Test
    void signupChecksTheNestedDetailsToo() {
        assertThat(invalidFields(signup("aarav.shah", "Passw0rd1", "Aarav Shah", "+91 9876543210", "aarav@example.com",
                details("123", "!!", "abc"))))
                .containsExactlyInAnyOrder("details.altPhone", "details.pinCode", "details.emergencyContact");
    }

    @Test
    void anAbsentOptionalDetailIsFine() {
        assertThat(invalidFields(signup("aarav.shah", "Passw0rd1", "Aarav Shah", "+91 9876543210", "aarav@example.com",
                details(null, null, null)))).isEmpty();
        assertThat(invalidFields(signup("aarav.shah", "Passw0rd1", "Aarav Shah", "+91 9876543210", "aarav@example.com",
                details("", "", "")))).isEmpty();
    }

    @Test
    void passwordChangeAndResetUseTheSamePolicy() {
        assertThat(invalidFields(new ChangePasswordRequest("old", "weak"))).containsExactly("newPassword");
        assertThat(invalidFields(new ChangePasswordRequest("old", "Strong123"))).isEmpty();
        assertThat(invalidFields(new ResetPasswordRequest("aarav", "123456", "abcdefgh"))).containsExactly("newPassword");
        assertThat(invalidFields(new ResetPasswordRequest("aarav", "123456", "abcdefg1"))).isEmpty();
    }

    @Test
    void academyOnboardingChecksBothPhonesAndTheAdminName() {
        var ok = new OnboardAcademyRequest("Owleo Arts", AcademyCategory.DANCE, null, "12 Main Rd", "Kochi", "Kerala",
                "+91 9876543210", "info@owleo.in", null, "admin.one", "Asha Menon", "+91 9876543211", "asha@owleo.in");
        assertThat(invalidFields(ok)).isEmpty();

        var bad = new OnboardAcademyRequest("Owleo Arts", AcademyCategory.DANCE, null, "12 Main Rd", "Kochi", "Kerala",
                "12345", "info@owleo", null, "a", "Asha 2", "999", "asha@");
        assertThat(invalidFields(bad)).containsExactlyInAnyOrder(
                "contactNumber", "email", "adminUsername", "adminFullName", "adminPhone", "adminEmail");
    }
}
