package com.nest.app.hq.service;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.YearMonth;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * The 12-month history behind the Dashboard, Growth and Finance charts. Each series has one value
 * per month, oldest first, the last one being the current month.
 *
 * <p>Users and academies are reconstructed from creation and closure dates, so the history is as
 * true as those dates are. Revenue comes from invoice lines (billed, before GST, waived bills left
 * out); expenses are what Finance has entered. When the current month has no invoices yet - bills
 * are raised on the 1st - the recurring revenue is ESTIMATED from the plans academies are on, so
 * the dashboard is not blank for the first day of every month. That estimate is only ever applied
 * to the current month.
 */
@Service
public class HqSeries {

    public static final int MONTHS = 12;
    public static final String[] EXPENSE_KEYS = {"SALARY", "CLOUD", "MARKETING", "SUPPORT", "MESSAGING", "MISC"};

    private final JdbcTemplate jdbc;
    private final HqAcademies academies;

    public HqSeries(JdbcTemplate jdbc, HqAcademies academies) {
        this.jdbc = jdbc;
        this.academies = academies;
    }

    public static List<String> months() {
        YearMonth now = YearMonth.now();
        List<String> out = new ArrayList<>();
        for (int i = MONTHS - 1; i >= 0; i--) {
            out.add(now.minusMonths(i).toString());
        }
        return out;
    }

    /** Everything the charts need, keyed by series name. */
    @Transactional(readOnly = true)
    public Map<String, Object> compute() {
        List<String> months = months();
        int n = months.size();
        String first = months.get(0);

        // ---- users: cumulative active members by role, as of the end of each month ----
        Map<String, long[]> role = new LinkedHashMap<>();
        for (String r : new String[]{"STUDENT", "TRAINER", "ACADEMY_ADMIN"}) {
            role.put(r, new long[n]);
        }
        jdbc.query("""
                SELECT to_char(created_at, 'YYYY-MM') AS m, role_type, count(*) AS c
                FROM academy_memberships WHERE status = 'ACTIVE' GROUP BY 1, 2""", rs -> {
            long[] arr = role.get(rs.getString("role_type"));
            if (arr == null) {
                return;
            }
            String m = rs.getString("m");
            int idx = m.compareTo(first) < 0 ? 0 : months.indexOf(m);
            if (idx >= 0) {
                arr[idx] += rs.getLong("c");
            }
        });
        role.values().forEach(HqSeries::cumulate);

        // ---- academies: active, added, churned ----
        long[] active = new long[n], added = new long[n], churned = new long[n], paying = new long[n];
        var rows = academies.all();
        for (var a : rows) {
            String joined = YearMonth.from(a.joined()).toString();
            int ji = joined.compareTo(first) < 0 ? -1 : months.indexOf(joined);
            String closed = a.closedAt() == null ? null : YearMonth.from(
                    a.closedAt().atZone(java.time.ZoneOffset.UTC)).toString();
            int ci = closed == null ? Integer.MAX_VALUE : (closed.compareTo(first) < 0 ? -1 : months.indexOf(closed));
            if (ji >= 0) {
                added[ji]++;
            }
            if (closed != null && ci >= 0) {
                churned[ci]++;
            }
            for (int m = 0; m < n; m++) {
                boolean started = ji <= m;
                boolean ended = closed != null && ci <= m;
                if (started && !ended) {
                    active[m]++;
                }
            }
        }

        // ---- money ----
        Map<String, double[]> byKind = new LinkedHashMap<>();
        for (String k : new String[]{"PLAN", "ADDON", "COMMISSION", "SETUP", "ADJUSTMENT", "MARKETING"}) {
            byKind.put(k, new double[n]);
        }
        jdbc.query("""
                SELECT i.period, l.kind, SUM(l.amount) AS amt
                FROM invoice_lines l JOIN academy_invoices i ON i.id = l.invoice_id
                WHERE i.status <> 'WAIVED' AND i.period >= ?
                GROUP BY 1, 2""", rs -> {
            int idx = months.indexOf(rs.getString("period"));
            double[] arr = byKind.get(rs.getString("kind"));
            if (idx >= 0 && arr != null) {
                arr[idx] += rs.getDouble("amt");
            }
        }, first);

        // Current month with nothing billed yet: estimate the recurring part from the plans.
        int cur = n - 1;
        boolean billedNow = byKind.values().stream().anyMatch(a -> a[cur] > 0);
        if (!billedNow) {
            byKind.get("PLAN")[cur] = rows.stream().filter(HqAcademies.Row::isPaying)
                    .mapToDouble(r -> r.planPrice().doubleValue()).sum();
        }
        for (var a : rows) {
            if (a.isPaying()) {
                paying[cur]++;
            }
        }
        // Earlier months' paying count = academies that were billed that month.
        jdbc.query("""
                SELECT period, count(DISTINCT academy_id) AS c FROM academy_invoices
                WHERE status <> 'WAIVED' AND period >= ? GROUP BY 1""", rs -> {
            int idx = months.indexOf(rs.getString("period"));
            if (idx >= 0 && idx < cur) {
                paying[idx] = rs.getLong("c");
            }
        }, first);

        double[] mrr = new double[n], revenue = new double[n];
        for (int m = 0; m < n; m++) {
            mrr[m] = byKind.get("PLAN")[m] + byKind.get("ADDON")[m];
            double sum = 0;
            for (double[] a : byKind.values()) {
                sum += a[m];
            }
            revenue[m] = sum;
        }

        Map<String, double[]> exp = new LinkedHashMap<>();
        for (String k : EXPENSE_KEYS) {
            exp.put(k, new double[n]);
        }
        jdbc.query("SELECT month, category, amount FROM hq_expenses WHERE month >= ?", rs -> {
            int idx = months.indexOf(rs.getString("month"));
            double[] arr = exp.get(rs.getString("category"));
            if (idx >= 0 && arr != null) {
                arr[idx] = rs.getDouble("amount");
            }
        }, first);
        double[] expenses = new double[n], profit = new double[n];
        for (int m = 0; m < n; m++) {
            double s = 0;
            for (double[] a : exp.values()) {
                s += a[m];
            }
            expenses[m] = s;
            profit[m] = revenue[m] - s;
        }

        long[] users = new long[n];
        for (int m = 0; m < n; m++) {
            users[m] = role.get("STUDENT")[m] + role.get("TRAINER")[m] + role.get("ACADEMY_ADMIN")[m];
        }

        Map<String, Object> out = new LinkedHashMap<>();
        out.put("months", months);
        out.put("students", role.get("STUDENT"));
        out.put("trainers", role.get("TRAINER"));
        out.put("admins", role.get("ACADEMY_ADMIN"));
        out.put("users", users);
        out.put("academies", active);
        out.put("added", added);
        out.put("churned", churned);
        out.put("paying", paying);
        out.put("mrr", mrr);
        out.put("revenue", revenue);
        out.put("expenses", expenses);
        out.put("profit", profit);
        Map<String, Object> streams = new HashMap<>();
        byKind.forEach((k, v) -> streams.put(k.toLowerCase(), v));
        out.put("streams", streams);
        Map<String, Object> expOut = new LinkedHashMap<>();
        exp.forEach((k, v) -> expOut.put(k.toLowerCase(), v));
        out.put("expenseLines", expOut);
        return out;
    }

    private static void cumulate(long[] a) {
        for (int i = 1; i < a.length; i++) {
            a[i] += a[i - 1];
        }
    }
}
