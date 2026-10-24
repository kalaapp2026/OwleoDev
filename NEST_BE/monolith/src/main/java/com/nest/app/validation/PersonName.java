package com.nest.app.validation;

import jakarta.validation.Constraint;
import jakarta.validation.Payload;

import java.lang.annotation.Documented;
import java.lang.annotation.ElementType;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;

/**
 * A person's name in any script: letters and combining marks with spaces between them. No digits or symbols.
 *
 * <p>Null and blank pass: say a field is required with {@code @NotBlank} beside this.
 */
@Documented
@Constraint(validatedBy = FieldRules.PersonNameValidator.class)
@Target({ElementType.METHOD, ElementType.FIELD, ElementType.ANNOTATION_TYPE, ElementType.CONSTRUCTOR, ElementType.PARAMETER, ElementType.TYPE_USE})
@Retention(RetentionPolicy.RUNTIME)
public @interface PersonName {

    String message() default "A name can only have letters and spaces (2 to 60 characters).";

    Class<?>[] groups() default {};

    Class<? extends Payload>[] payload() default {};
}
