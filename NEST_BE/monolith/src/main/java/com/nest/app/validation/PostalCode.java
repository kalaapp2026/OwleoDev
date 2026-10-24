package com.nest.app.validation;

import jakarta.validation.Constraint;
import jakarta.validation.Payload;

import java.lang.annotation.Documented;
import java.lang.annotation.ElementType;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;

/**
 * A postal / PIN code: 3-10 letters, digits, spaces or hyphens. India's six-digit PIN fits.
 *
 * <p>Null and blank pass: say a field is required with {@code @NotBlank} beside this.
 */
@Documented
@Constraint(validatedBy = FieldRules.PostalCodeValidator.class)
@Target({ElementType.METHOD, ElementType.FIELD, ElementType.ANNOTATION_TYPE, ElementType.CONSTRUCTOR, ElementType.PARAMETER, ElementType.TYPE_USE})
@Retention(RetentionPolicy.RUNTIME)
public @interface PostalCode {

    String message() default "That postal code looks wrong.";

    Class<?>[] groups() default {};

    Class<? extends Payload>[] payload() default {};
}
