package com.nest.app.validation;

import jakarta.validation.Constraint;
import jakarta.validation.Payload;

import java.lang.annotation.Documented;
import java.lang.annotation.ElementType;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;

/**
 * A login id: 3-30 characters of letters, digits and . _ - , starting and ending with a letter or digit.
 *
 * <p>Null and blank pass: say a field is required with {@code @NotBlank} beside this.
 */
@Documented
@Constraint(validatedBy = FieldRules.UsernameValidator.class)
@Target({ElementType.METHOD, ElementType.FIELD, ElementType.ANNOTATION_TYPE, ElementType.CONSTRUCTOR, ElementType.PARAMETER, ElementType.TYPE_USE})
@Retention(RetentionPolicy.RUNTIME)
public @interface Username {

    String message() default "A username is 3 to 30 characters: letters, numbers and . _ - only, starting and ending with a letter or number.";

    Class<?>[] groups() default {};

    Class<? extends Payload>[] payload() default {};
}
