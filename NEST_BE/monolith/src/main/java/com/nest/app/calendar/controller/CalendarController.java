package com.nest.app.calendar.controller;

import com.nest.app.calendar.dto.CalendarClassResponse;
import com.nest.app.calendar.service.CalendarService;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.time.LocalDate;
import java.util.List;

@RestController
@Tag(name = "Calendar")
public class CalendarController {

    private final CalendarService calendarService;

    public CalendarController(CalendarService calendarService) {
        this.calendarService = calendarService;
    }

    /** PRD 7.5 - merged across every academy the caller belongs to, not just the active one; see
     * {@link CalendarService} for why this endpoint is deliberately not @RequiresFeature-gated
     * the way everything else is (there's no single "active membership" to gate against here). */
    @GetMapping("/calendar/classes")
    public List<CalendarClassResponse> classes(@RequestParam @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate from,
                                                @RequestParam @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate to) {
        return calendarService.classesForCaller(from, to);
    }
}
