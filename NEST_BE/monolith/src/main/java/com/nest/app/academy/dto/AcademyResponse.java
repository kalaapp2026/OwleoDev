package com.nest.app.academy.dto;

import com.nest.app.academy.entity.AcademyCategory;
import com.nest.app.academy.entity.AcademyStatus;

import java.util.UUID;

public record AcademyResponse(
        UUID id,
        String name,
        AcademyCategory category,
        String logoUrl,
        String address,
        String city,
        String state,
        String contactNumber,
        String email,
        String plan,
        AcademyStatus status
) {
}
