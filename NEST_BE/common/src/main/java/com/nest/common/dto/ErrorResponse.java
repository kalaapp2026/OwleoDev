package com.nest.common.dto;

import java.time.Instant;
import java.util.List;
import java.util.Map;

/**
 * Consistent error shape returned by every NEST service.
 */
public record ErrorResponse(
        Instant timestamp,
        int status,
        String error,
        String code,
        String message,
        String path,
        List<Map<String, String>> validationErrors
) {
    public static ErrorResponse of(int status, String error, String code, String message, String path) {
        return new ErrorResponse(Instant.now(), status, error, code, message, path, null);
    }

    public static ErrorResponse withValidation(int status, String error, String code, String message, String path,
                                                 List<Map<String, String>> validationErrors) {
        return new ErrorResponse(Instant.now(), status, error, code, message, path, validationErrors);
    }
}
