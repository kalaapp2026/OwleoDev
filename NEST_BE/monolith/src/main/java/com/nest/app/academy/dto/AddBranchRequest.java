package com.nest.app.academy.dto;

import jakarta.validation.constraints.NotBlank;

public record AddBranchRequest(@NotBlank String name, String address) {
}
