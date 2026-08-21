package com.nest.common.exception;

import com.nest.common.dto.ErrorResponse;
import jakarta.servlet.http.HttpServletRequest;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.core.AuthenticationException;
import org.springframework.web.bind.MethodArgumentNotValidException;
import com.fasterxml.jackson.databind.exc.InvalidFormatException;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.servlet.resource.NoResourceFoundException;

import java.util.Arrays;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

/**
 * Every NEST service picks this up automatically via {@code common}'s auto-configuration.
 * Keeps the error JSON shape identical across all 11 services so the Flutter client has one
 * error-parsing code path.
 */
@RestControllerAdvice
public class GlobalExceptionHandler {

    private static final Logger log = LoggerFactory.getLogger(GlobalExceptionHandler.class);

    @ExceptionHandler(NestException.class)
    public ResponseEntity<ErrorResponse> handleNestException(NestException ex, HttpServletRequest request) {
        if (ex.getStatus().is5xxServerError()) {
            log.error("Unhandled NestException on {}", request.getRequestURI(), ex);
        }
        return ResponseEntity.status(ex.getStatus())
                .body(ErrorResponse.of(ex.getStatus().value(), ex.getStatus().getReasonPhrase(), ex.getCode(),
                        ex.getMessage(), request.getRequestURI()));
    }

    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ResponseEntity<ErrorResponse> handleValidation(MethodArgumentNotValidException ex, HttpServletRequest request) {
        List<Map<String, String>> errors = ex.getBindingResult().getFieldErrors().stream()
                .map(fe -> Map.of("field", fe.getField(), "message", String.valueOf(fe.getDefaultMessage())))
                .collect(Collectors.toList());
        return ResponseEntity.status(HttpStatus.BAD_REQUEST)
                .body(ErrorResponse.withValidation(HttpStatus.BAD_REQUEST.value(), "Bad Request", "VALIDATION_FAILED",
                        "Request failed validation", request.getRequestURI(), errors));
    }

    @ExceptionHandler(AccessDeniedException.class)
    public ResponseEntity<ErrorResponse> handleAccessDenied(AccessDeniedException ex, HttpServletRequest request) {
        return ResponseEntity.status(HttpStatus.FORBIDDEN)
                .body(ErrorResponse.of(HttpStatus.FORBIDDEN.value(), "Forbidden", "FORBIDDEN",
                        ex.getMessage(), request.getRequestURI()));
    }

    @ExceptionHandler(AuthenticationException.class)
    public ResponseEntity<ErrorResponse> handleAuthentication(AuthenticationException ex, HttpServletRequest request) {
        return ResponseEntity.status(HttpStatus.UNAUTHORIZED)
                .body(ErrorResponse.of(HttpStatus.UNAUTHORIZED.value(), "Unauthorized", "UNAUTHORIZED",
                        ex.getMessage(), request.getRequestURI()));
    }

    /** Spring 6.1+'s replacement for "no handler found" - e.g. a typo'd path, or (before this
     * handler existed) an actuator endpoint whose starter wasn't on the classpath. Without this,
     * it fell through to the generic 500 handler below, which is wrong: a missing route is a
     * client-side 404, not a server fault. */
    @ExceptionHandler(NoResourceFoundException.class)
    public ResponseEntity<ErrorResponse> handleNoResourceFound(NoResourceFoundException ex, HttpServletRequest request) {
        return ResponseEntity.status(HttpStatus.NOT_FOUND)
                .body(ErrorResponse.of(HttpStatus.NOT_FOUND.value(), "Not Found", "NOT_FOUND",
                        "No endpoint matches " + request.getMethod() + " " + request.getRequestURI(), request.getRequestURI()));
    }

    /** An unparseable body - malformed JSON, or a value that doesn't fit its field, most often an
     * unknown enum constant. Without this it fell through to the 500 below, which points the
     * reader at a server fault when the request itself was wrong. */
    @ExceptionHandler(HttpMessageNotReadableException.class)
    public ResponseEntity<ErrorResponse> handleUnreadableBody(HttpMessageNotReadableException ex,
                                                              HttpServletRequest request) {
        return ResponseEntity.status(HttpStatus.BAD_REQUEST)
                .body(ErrorResponse.of(HttpStatus.BAD_REQUEST.value(), "Bad Request", "MALFORMED_REQUEST",
                        describeUnreadable(ex), request.getRequestURI()));
    }

    /** Jackson's own message leaks package names and class internals, so name the offending value
     * and its allowed options instead - that's what the caller can act on. */
    private String describeUnreadable(HttpMessageNotReadableException ex) {
        if (ex.getCause() instanceof InvalidFormatException invalid) {
            Class<?> target = invalid.getTargetType();
            if (target != null && target.isEnum()) {
                String allowed = Arrays.stream(target.getEnumConstants())
                        .map(String::valueOf).collect(Collectors.joining(", "));
                return "'" + invalid.getValue() + "' is not a valid value. Expected one of: " + allowed;
            }
        }
        return "Request body could not be read - check the JSON and field types";
    }

    @ExceptionHandler(Exception.class)
    public ResponseEntity<ErrorResponse> handleGeneric(Exception ex, HttpServletRequest request) {
        log.error("Unhandled exception on {}", request.getRequestURI(), ex);
        return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                .body(ErrorResponse.of(HttpStatus.INTERNAL_SERVER_ERROR.value(), "Internal Server Error",
                        "INTERNAL_ERROR", "An unexpected error occurred", request.getRequestURI()));
    }
}
