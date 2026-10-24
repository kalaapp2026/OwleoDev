package com.nest.app.validation;

import jakarta.validation.Constraint;
import jakarta.validation.Payload;

import java.lang.annotation.Documented;
import java.lang.annotation.ElementType;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;

/**
 * A phone number that is real in its own country. Written without a country code it is read as Indian.
 * {@link #mobileOnly()} also refuses a number that is certainly a landline.
 *
 * <p>Null and blank pass: say a field is required with {@code @NotBlank} beside this.
 */
@Documented
@Constraint(validatedBy = FieldRules.PhoneValidator.class)
@Target({ElementType.METHOD, ElementType.FIELD, ElementType.ANNOTATION_TYPE, ElementType.CONSTRUCTOR, ElementType.PARAMETER, ElementType.TYPE_USE})
@Retention(RetentionPolicy.RUNTIME)
public @interface Phone {

    String message() default "Enter a valid phone number, with its country code (for example +91 9876543210).";

    /** Refuse landlines: this number receives OTPs and WhatsApp messages. */
    boolean mobileOnly() default true;

    Class<?>[] groups() default {};

    Class<? extends Payload>[] payload() default {};
}
