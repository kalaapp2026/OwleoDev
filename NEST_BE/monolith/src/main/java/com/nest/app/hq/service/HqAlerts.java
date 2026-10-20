package com.nest.app.hq.service;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

/**
 * "Everything that needs a look today", worked out from live data each time it is asked for -
 * nothing is stored, so an alert disappears the moment the cause is fixed.
 */
@Service
public class HqAlerts {

    public record Alert(String kind, String tone, String icon, String title, String text, UUID academyId) {
    }

    private final HqAcademies academies;
    private final JdbcTemplate jdbc;

    public HqAlerts(HqAcademies academies, JdbcTemplate jdbc) {
        this.academies = academies;
        this.jdbc = jdbc;
    }

    @Transactional(readOnly = true)
    public List<Alert> all() {
        List<Alert> out = new ArrayList<>();
        var rows = academies.all();

        // Unpaid bills past their due date, one alert per academy.
        Map<UUID, BigDecimal> owed = new LinkedHashMap<>();
        jdbc.query("""
                SELECT i.academy_id, SUM(i.total - COALESCE((SELECT SUM(p.amount) FROM invoice_payments p WHERE p.invoice_id = i.id), 0)) AS bal
                FROM academy_invoices i WHERE i.status = 'DUE' AND i.due_on < current_date GROUP BY 1""",
                rs -> {
                    owed.put(rs.getObject("academy_id", UUID.class), rs.getBigDecimal("bal"));
                });
        for (var a : rows) {
            BigDecimal bal = owed.get(a.id());
            if (bal != null && bal.signum() > 0 && a.isOpen()) {
                out.add(new Alert("payment", "red", "wallet", "Payment overdue",
                        a.name() + ": " + inr(bal) + " unpaid past the due date", a.id()));
            }
        }

        for (var a : rows) {
            if (HqAcademies.TRIAL.equals(a.status()) && a.demoEndsOn() != null) {
                long days = ChronoUnit.DAYS.between(LocalDate.now(), a.demoEndsOn());
                if (days <= 14) {
                    out.add(new Alert("demo", "blue", "clock", "Demo ending",
                            a.name() + (days < 0 ? " demo ended " + (-days) + " days ago: convert or close"
                                    : " converts to paid or ends in " + days + " days"), a.id()));
                }
            }
        }

        for (var a : rows) {
            if ((HqAcademies.LIVE.equals(a.status()) || HqAcademies.PASTDUE.equals(a.status())) && a.maxStudents() != null && a.maxStudents() > 0
                    && a.students() >= a.maxStudents() * 0.9) {
                out.add(new Alert("limit", "gold", "users", "Near plan limit",
                        a.name() + " is at " + a.students() + " of " + a.maxStudents() + " students: upsell to a bigger plan", a.id()));
            }
        }

        for (var a : rows) {
            if ((HqAcademies.LIVE.equals(a.status()) || HqAcademies.PASTDUE.equals(a.status()))
                    && a.weeklyActive() != null && a.weeklyActive() < 50 && a.users() >= 5) {
                out.add(new Alert("engagement", "coral", "pulse", "Low engagement",
                        a.name() + ": only " + a.weeklyActive() + "% of users active this week", a.id()));
            }
        }
        return out;
    }

    private static String inr(BigDecimal v) {
        return "₹" + java.text.NumberFormat.getIntegerInstance(new java.util.Locale("en", "IN")).format(v.setScale(0, java.math.RoundingMode.HALF_UP));
    }
}
