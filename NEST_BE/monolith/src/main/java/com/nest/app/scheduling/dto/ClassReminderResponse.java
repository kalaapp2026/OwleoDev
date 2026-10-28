package com.nest.app.scheduling.dto;

import java.time.Instant;

/** Who a class reminder went to, so the screen can say "Reminder sent to 12 students and 2 trainers". */
public record ClassReminderResponse(int students, int trainers, Instant remindedAt) {
}
