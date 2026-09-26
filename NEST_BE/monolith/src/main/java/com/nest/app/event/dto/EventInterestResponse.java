package com.nest.app.event.dto;

import java.util.List;

public record EventInterestResponse(int count, List<InterestedPersonResponse> interested) {
}
