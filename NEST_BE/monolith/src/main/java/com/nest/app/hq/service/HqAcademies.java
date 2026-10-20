package com.nest.app.hq.service;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.sql.Timestamp;
import java.time.Instant;
import java.time.LocalDate;
import java.util.Comparator;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import java.util.function.Function;
import java.util.stream.Collectors;

/**
 * The HQ view of an academy: who they are, how big they are, whether they are paying, and a
 * health score. Everything in the console that lists or ranks academies reads this, so the
 * numbers on the dashboard, the Entities list and the Alerts page can never disagree.
 *
 * <p>Status is derived, not stored:
 * <pre>closed -> churned | SUSPENDED -> suspended | on demo -> trial | overdue bill -> pastdue | else live</pre>
 */
@Service
public class HqAcademies {

    /** The ids the console uses for a status; the web app maps them to a label and colour. */
    public static final String LIVE = "live", TRIAL = "trial", PASTDUE = "pastdue",
            CHURNED = "churned", SUSPENDED = "suspended";

    private final JdbcTemplate jdbc;

    public HqAcademies(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public record Row(
            UUID id, String name, String city, String type, String plan, String planName,
            BigDecimal planPrice, Integer maxStudents, Integer maxTrainers, String status,
            LocalDate joined, String owner, int students, int trainers, int admins,
            int courses, int batches, Integer attendance, Integer feeCollection, Integer weeklyActive,
            int health, Instant lastActive, LocalDate demoEndsOn, Instant closedAt, boolean overdue) {

        public int users() {
            return students + trainers + admins;
        }

        /** True while the academy counts toward "active academies" (everything but churned). */
        public boolean isOpen() {
            return !CHURNED.equals(status);
        }

        /** Paying a plan price right now: live or past due, with a priced plan. */
        public boolean isPaying() {
            return (LIVE.equals(status) || PASTDUE.equals(status)) && planPrice != null && planPrice.signum() > 0;
        }
    }

    private static final String SQL = """
            SELECT a.id, a.name, a.city, a.category, a.plan, a.status, a.created_at, a.owner_name,
                   a.demo_ends_on, a.go_live_on, a.closed_at,
                   p.display_name AS plan_name, p.monthly_price, p.max_students, p.max_trainers,
                   (SELECT count(*) FROM academy_memberships m WHERE m.academy_id = a.id AND m.role_type = 'STUDENT' AND m.status = 'ACTIVE') AS students,
                   (SELECT count(*) FROM academy_memberships m WHERE m.academy_id = a.id AND m.role_type = 'TRAINER' AND m.status = 'ACTIVE') AS trainers,
                   (SELECT count(*) FROM academy_memberships m WHERE m.academy_id = a.id AND m.role_type = 'ACADEMY_ADMIN' AND m.status = 'ACTIVE') AS admins,
                   (SELECT count(*) FROM courses c WHERE c.academy_id = a.id AND c.status = 'ACTIVE') AS courses,
                   (SELECT count(*) FROM batches b JOIN courses c ON c.id = b.course_id WHERE c.academy_id = a.id AND b.status = 'ACTIVE') AS batches,
                   (SELECT round(100.0 * count(*) FILTER (WHERE at.status = 'PRESENT') / NULLIF(count(*), 0))
                      FROM attendance at JOIN class_instances ci ON ci.id = at.class_instance_id
                      JOIN batches b ON b.id = ci.batch_id JOIN courses c ON c.id = b.course_id
                     WHERE c.academy_id = a.id AND ci.date >= current_date - 30) AS attendance,
                   (SELECT COALESCE(SUM(fs.amount_due), 0) FROM fee_slips fs JOIN academy_memberships m ON m.id = fs.membership_id
                     WHERE m.academy_id = a.id AND fs.billing_period_end >= current_date - 60) AS fee_due,
                   (SELECT COALESCE(SUM(ft.amount_paid), 0) FROM fee_transactions ft
                     WHERE ft.academy_id = a.id AND ft.reversal_of_transaction_id IS NULL AND ft.occurred_on >= current_date - 60) AS fee_paid,
                   (SELECT round(100.0 * count(*) FILTER (WHERE u.last_seen_at >= now() - interval '7 days') / NULLIF(count(*), 0))
                      FROM academy_memberships m JOIN users u ON u.id = m.user_id WHERE m.academy_id = a.id AND m.status = 'ACTIVE') AS weekly_active,
                   (SELECT max(u.last_seen_at) FROM academy_memberships m JOIN users u ON u.id = m.user_id WHERE m.academy_id = a.id) AS last_active,
                   EXISTS (SELECT 1 FROM academy_invoices i WHERE i.academy_id = a.id AND i.status = 'DUE' AND i.due_on < current_date) AS overdue
            FROM academies a LEFT JOIN billing_plans p ON p.code = a.plan
            """;

    @Transactional(readOnly = true)
    public List<Row> all() {
        return jdbc.query(SQL + " ORDER BY a.name", (rs, i) -> {
            boolean overdue = rs.getBoolean("overdue");
            Timestamp closed = rs.getTimestamp("closed_at");
            String statusCol = rs.getString("status");
            LocalDate demo = rs.getObject("demo_ends_on", LocalDate.class);
            String status = closed != null ? CHURNED
                    : "SUSPENDED".equals(statusCol) ? SUSPENDED
                    : demo != null ? TRIAL
                    : overdue ? PASTDUE : LIVE;

            double due = rs.getDouble("fee_due");
            Integer fee = due > 0 ? (int) Math.min(100, Math.round(100 * rs.getDouble("fee_paid") / due)) : null;
            Integer att = nullableInt(rs.getObject("attendance"));
            Integer wau = nullableInt(rs.getObject("weekly_active"));

            Timestamp last = rs.getTimestamp("last_active");
            LocalDate joined = rs.getObject("go_live_on", LocalDate.class);
            if (joined == null) {
                joined = rs.getTimestamp("created_at").toLocalDateTime().toLocalDate();
            }
            return new Row(
                    rs.getObject("id", UUID.class), rs.getString("name"), rs.getString("city"),
                    typeLabel(rs.getString("category")), rs.getString("plan"), rs.getString("plan_name"),
                    rs.getBigDecimal("monthly_price"), (Integer) rs.getObject("max_students"),
                    (Integer) rs.getObject("max_trainers"), status, joined, rs.getString("owner_name"),
                    rs.getInt("students"), rs.getInt("trainers"), rs.getInt("admins"),
                    rs.getInt("courses"), rs.getInt("batches"), att, fee, wau,
                    health(att, fee, wau), last == null ? null : last.toInstant(), demo,
                    closed == null ? null : closed.toInstant(), overdue);
        });
    }

    @Transactional(readOnly = true)
    public Optional<Row> one(UUID id) {
        return all().stream().filter(r -> r.id().equals(id)).findFirst();
    }

    public Map<UUID, Row> byId() {
        return all().stream().collect(Collectors.toMap(Row::id, Function.identity()));
    }

    /** Health = attendance 30%, fee collection 35%, weekly activity 35%. A missing component (an
     * academy with no classes yet) drops out and the rest re-weight, so a brand-new academy is not
     * scored zero for having no history. */
    static int health(Integer att, Integer fee, Integer wau) {
        double sum = 0, weight = 0;
        if (att != null) { sum += att * .30; weight += .30; }
        if (fee != null) { sum += fee * .35; weight += .35; }
        if (wau != null) { sum += wau * .35; weight += .35; }
        return weight == 0 ? 0 : (int) Math.round(sum / weight);
    }

    private static Integer nullableInt(Object o) {
        return o == null ? null : Integer.valueOf(((Number) o).intValue());
    }

    public static String typeLabel(String category) {
        if (category == null) {
            return "Multi";
        }
        return switch (category) {
            case "DANCE" -> "Dance";
            case "MUSIC" -> "Music";
            case "FINE_ARTS" -> "Fine Arts";
            case "THEATRE" -> "Theatre";
            default -> "Multi";
        };
    }

    /** The inverse of {@link #typeLabel}, for forms that send the console's label. */
    public static String categoryOf(String label) {
        if (label == null) {
            return "MULTI_DISCIPLINE";
        }
        return switch (label) {
            case "Dance" -> "DANCE";
            case "Music" -> "MUSIC";
            case "Fine Arts" -> "FINE_ARTS";
            case "Theatre" -> "THEATRE";
            default -> "MULTI_DISCIPLINE";
        };
    }

    public static Comparator<Row> byHealthDesc() {
        return Comparator.comparingInt(Row::health).reversed();
    }
}
