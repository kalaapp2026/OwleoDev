package com.nest.app.academy.dto;

import com.nest.app.academy.entity.AcademyRequestStatus;
import com.nest.app.academy.entity.AcademyRequestType;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.List;
import java.util.UUID;

/** Wire shapes for Academy Settings, grouped since they are small and only used together. */
public final class AcademySettingsDtos {

    private AcademySettingsDtos() {
    }

    public record SettingsResponse(UUID academyId, String name, String ownerName, String defaultLanguage) {
    }

    public record LanguageRequest(@NotBlank @Size(max = 10) String defaultLanguage) {
    }

    public record PlanSummary(String code, String displayName, BigDecimal monthlyPrice,
                              Integer maxStudents, Integer maxTrainers) {
    }

    /** The academy's plan, how much of it is used, and the plans it could move to. A null limit
     * means the plan has no cap on that count. */
    public record SubscriptionResponse(PlanSummary current, long students, long trainers, List<PlanSummary> plans) {
    }

    public record CreateRequest(
            @NotNull AcademyRequestType type,
            @Size(max = 200) String subject,
            @Size(max = 2000) String details,
            @Size(max = 255) String targetEmail,
            @Size(max = 80) String reason,
            @Size(max = 40) String targetPlan
    ) {
    }

    public record RequestResponse(UUID id, UUID academyId, String academyName, String requestedByName,
                                  AcademyRequestType type, AcademyRequestStatus status, String subject,
                                  String details, String targetEmail, String reason, String targetPlan,
                                  String resolutionNote, Instant createdAt, Instant resolvedAt) {
    }

    public record ResolveRequest(@NotNull Boolean approve, @Size(max = 1000) String note) {
    }

    public record ExportResponse(UUID id, String kind, String fileName, int rowCount, long sizeBytes, Instant createdAt) {
    }
}
