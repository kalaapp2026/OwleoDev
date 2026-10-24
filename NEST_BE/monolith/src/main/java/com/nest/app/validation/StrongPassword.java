package com.nest.app.validation;

import jakarta.validation.Constraint;
import jakarta.validation.Payload;

import java.lang.annotation.Documented;
import java.lang.annotation.ElementType;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;

/**
 * A password of 8-72 characters with at least one letter and one digit and no leading or trailing space.
 *
 * <p>Null and blank pass: say a field is required with {@code @NotBlank} beside this.
 */
@Documented
@Constraint(validatedBy = FieldRules.PasswordValidator.class)
@Target({ElementType.METHOD, ElementType.FIELD, ElementType.ANNOTATION_TYPE, ElementType.CONSTRUCTOR, ElementType.PARAMETER, ElementType.TYPE_USE})
@Retention(RetentionPolicy.RUNTIME)
public @interface StrongPassword {

    String message() default "Use 8 to 72 characters with at least one letter and one number.";

    Class<?>[] groups() default {};

    Class<? extends Payload>[] payload() default {};
}
