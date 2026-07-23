package com.nest.academy.dto;

import com.nest.academy.entity.AcademyCategory;
import com.nest.academy.entity.AcademyStatus;

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
