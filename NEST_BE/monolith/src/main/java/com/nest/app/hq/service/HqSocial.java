package com.nest.app.hq.service;

import com.nest.app.hq.HqAudit;
import com.nest.app.platform.entity.AppMode;
import com.nest.app.platform.service.PlatformSettingsService;
import com.nest.common.exception.BadRequestException;
import com.nest.common.exception.ResourceNotFoundException;
import com.nest.common.security.TenantContext;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.sql.Timestamp;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

/**
 * HQ's view of Owleo Social: the feed (with removal for moderation), posting as the official
 * Owleo account, search across the platform, and how the official page is doing. The product
 * records no likes, comments or reports yet, so none are shown here.
 */
@Service
public class HqSocial {

    private final JdbcTemplate jdbc;
    private final HqAudit audit;
    private final PlatformSettingsService settings;

    public HqSocial(JdbcTemplate jdbc, HqAudit audit, PlatformSettingsService settings) {
        this.jdbc = jdbc;
        this.audit = audit;
        this.settings = settings;
    }

    public Map<String, Object> feed(int limit) {
        UUID me = TenantContext.currentUserIdOrNull();
        List<Map<String, Object>> posts = new ArrayList<>();
        for (var p : jdbc.queryForList("""
                SELECT p.id, p.content, p.visibility, p.created_at, p.event_id, p.author_user_id, p.author_membership_id,
                       COALESCE(a.name, u.full_name, 'Unknown') AS author, a.city AS academy_city, a.category AS academy_category,
                       (SELECT count(*) FROM post_media_urls pm WHERE pm.post_id = p.id) AS media,
                       (SELECT count(*) FROM interests i WHERE i.post_id = p.id) AS interested,
                       u.role_type AS author_role
                FROM posts p
                LEFT JOIN academy_memberships m ON m.id = p.author_membership_id
                LEFT JOIN academies a ON a.id = m.academy_id
                LEFT JOIN users u ON u.id = p.author_user_id
                ORDER BY p.created_at DESC LIMIT ?""", limit)) {
            boolean official = p.get("author_user_id") != null && "SUPER_ADMIN".equals(p.get("author_role"));
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("id", p.get("id"));
            m.put("text", p.get("content"));
            m.put("author", official ? "Owleo" : p.get("author"));
            m.put("sub", official ? "Official · HQ" : p.get("author_membership_id") != null ? nz(p.get("academy_city")) + " · " + HqAcademies.typeLabel((String) p.get("academy_category")) : nz(p.get("author_role")));
            m.put("official", official);
            m.put("kind", official ? "hq" : p.get("author_membership_id") != null ? "academy" : "artist");
            m.put("public", "PUBLIC".equals(p.get("visibility")));
            m.put("at", ((Timestamp) p.get("created_at")).toInstant());
            m.put("media", p.get("media"));
            m.put("interested", p.get("interested"));
            m.put("mine", me != null && me.equals(p.get("author_user_id")));
            posts.add(m);
        }
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("posts", posts);
        out.put("socialUsers", jdbc.queryForObject("SELECT count(*) FROM users WHERE role_type IN ('GUEST', 'ARTIST') OR id IN (SELECT user_id FROM academy_memberships WHERE status = 'ACTIVE')", Integer.class));
        out.put("postsTotal", jdbc.queryForObject("SELECT count(*) FROM posts", Integer.class));
        out.put("postsWeek", jdbc.queryForObject("SELECT count(*) FROM posts WHERE created_at > now() - interval '7 days'", Integer.class));
        AppMode mode = settings.current().getAppMode();
        out.put("socialVisible", mode.allowsSocial());
        return out;
    }

    @Transactional
    public UUID post(String text) {
        String t = text == null ? "" : text.trim();
        if (t.length() < 3) throw new BadRequestException("Write something to post.");
        if (t.length() > 2000) throw new BadRequestException("Keep the post under 2000 characters.");
        UUID me = TenantContext.currentUserId();
        UUID id = UUID.randomUUID();
        jdbc.update("INSERT INTO posts (id, author_user_id, type, content, visibility) VALUES (?, ?, 'NORMAL', ?, 'PUBLIC')", id, me, t);
        audit.log("social", "Posted as Owleo: " + (t.length() > 80 ? t.substring(0, 80) + "…" : t));
        return id;
    }

    @Transactional
    public void remove(UUID id) {
        var p = jdbc.queryForList("SELECT left(content, 80) AS c FROM posts WHERE id = ?", id);
        if (p.isEmpty()) throw new ResourceNotFoundException("Post not found");
        jdbc.update("DELETE FROM post_media_urls WHERE post_id = ?", id);
        jdbc.update("DELETE FROM interests WHERE post_id = ?", id);
        jdbc.update("DELETE FROM posts WHERE id = ?", id);
        audit.log("social", "Removed a post: " + p.get(0).get("c"));
    }

    public Map<String, Object> search(String q, String filter) {
        String needle = q == null ? "" : q.trim();
        String like = "%" + needle.toLowerCase() + "%";
        boolean all = filter == null || filter.equals("all");
        int lim = all ? 4 : 30;
        Map<String, Object> out = new LinkedHashMap<>();
        if (all || "academies".equals(filter)) {
            out.put("academies", jdbc.queryForList("""
                    SELECT a.id, a.name, a.city || ' · ' || (SELECT count(*) FROM academy_memberships m WHERE m.academy_id = a.id AND m.status = 'ACTIVE') || ' users' AS sub, a.category
                    FROM academies a WHERE a.closed_at IS NULL AND (? = '' OR lower(a.name || ' ' || a.city) LIKE ?) ORDER BY a.name LIMIT ?""", needle, like, lim));
        }
        if (all || "people".equals(filter)) {
            out.put("people", jdbc.queryForList("""
                    SELECT a.owner_name AS name, 'Owner · ' || a.name AS sub, a.id AS "academyId" FROM academies a
                    WHERE a.closed_at IS NULL AND a.owner_name IS NOT NULL AND (? = '' OR lower(a.owner_name || ' ' || a.name) LIKE ?) ORDER BY a.owner_name LIMIT ?""", needle, like, lim));
        }
        if (all || "posts".equals(filter)) {
            out.put("posts", jdbc.queryForList("""
                    SELECT p.id, CASE WHEN u.role_type = 'SUPER_ADMIN' THEN 'Owleo' ELSE COALESCE(a.name, u.full_name, 'Unknown') END AS name, left(p.content, 90) AS sub
                    FROM posts p LEFT JOIN academy_memberships m ON m.id = p.author_membership_id LEFT JOIN academies a ON a.id = m.academy_id LEFT JOIN users u ON u.id = p.author_user_id
                    WHERE (? = '' OR lower(p.content) LIKE ?) ORDER BY p.created_at DESC LIMIT ?""", needle, like, lim));
        }
        if (all || "events".equals(filter)) {
            out.put("events", jdbc.queryForList("""
                    SELECT e.id, e.title AS name, to_char(e.event_date, 'DD Mon') || ' · ' || COALESCE(e.location, a.name) AS sub
                    FROM events e JOIN academies a ON a.id = e.academy_id WHERE e.status = 'PUBLISHED' AND (? = '' OR lower(e.title || ' ' || COALESCE(e.location, '')) LIKE ?) ORDER BY e.event_date DESC LIMIT ?""", needle, like, lim));
        }
        return out;
    }

    /** The official page: totals, and how many posts went out each week. */
    public Map<String, Object> profile() {
        List<Map<String, Object>> weeks = new ArrayList<>();
        LocalDate monday = LocalDate.now().with(java.time.DayOfWeek.MONDAY);
        for (int i = 11; i >= 0; i--) {
            LocalDate from = monday.minusWeeks(i);
            Integer n = jdbc.queryForObject("SELECT count(*) FROM posts WHERE created_at >= ? AND created_at < ?", Integer.class, Timestamp.valueOf(from.atStartOfDay()), Timestamp.valueOf(from.plusWeeks(1).atStartOfDay()));
            weeks.add(Map.of("week", from.toString(), "posts", n == null ? 0 : n));
        }
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("followers", jdbc.queryForObject("SELECT count(*) FROM users WHERE role_type <> 'SUPER_ADMIN'", Integer.class));
        out.put("academies", jdbc.queryForObject("SELECT count(*) FROM academies WHERE closed_at IS NULL", Integer.class));
        out.put("officialPosts", jdbc.queryForObject("SELECT count(*) FROM posts p JOIN users u ON u.id = p.author_user_id WHERE u.role_type = 'SUPER_ADMIN'", Integer.class));
        out.put("weeks", weeks);
        out.put("top", jdbc.queryForList("""
                SELECT p.id, left(p.content, 70) AS text, (SELECT count(*) FROM interests i WHERE i.post_id = p.id) AS interested
                FROM posts p ORDER BY interested DESC, p.created_at DESC LIMIT 3"""));
        return out;
    }

    private static String nz(Object o) {
        return o == null ? "" : o.toString();
    }
}
