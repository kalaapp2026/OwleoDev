package com.nest.app.hq.service;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.nest.app.hq.HqAudit;
import com.nest.common.exception.BadRequestException;
import com.nest.common.exception.ConflictException;
import com.nest.common.exception.ResourceNotFoundException;
import com.nest.common.security.TenantContext;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.YearMonth;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.regex.Pattern;

/**
 * Service providers academies can hire for events. Owleo's job is to vet them: portfolio links
 * that work, ID proof, a verification call, then go live. Requests from academies are passed on to
 * suitable providers; a hire becomes a job, and how each job went is the only source of a
 * provider's rating and reliability. Owleo stores no photos, videos or audio.
 */
@Service
public class HqProviders {

    private static final Pattern EMAIL = Pattern.compile("^\\S+@\\S+\\.\\S+$");
    private static final Pattern MOBILE = Pattern.compile("^[6-9]\\d{9}$");
    private static final Pattern URL = Pattern.compile("^https?://\\S+\\.\\S+$");
    private static final List<String[]> KYC = List.of(
            new String[]{"id", "ID proof seen", "Owner ID card checked"},
            new String[]{"biz", "Business proof", "GST or shop licence (optional)"},
            new String[]{"call", "Verification call done", "Spoke to the owner"},
            new String[]{"refs", "Reference checked", "One past client confirmed"});

    private final JdbcTemplate jdbc;
    private final HqAudit audit;
    private final ObjectMapper json;

    public HqProviders(JdbcTemplate jdbc, HqAudit audit, ObjectMapper json) {
        this.jdbc = jdbc;
        this.audit = audit;
        this.json = json;
    }

    private static String ref(long seq) {
        return "SV-" + (100 + seq);
    }

    // ---------------------------------------------------------------- helpers

    private List<Map<String, Object>> links(Object raw) {
        try {
            return json.readValue(raw == null ? "[]" : raw.toString(), new TypeReference<>() { });
        } catch (Exception e) {
            return new ArrayList<>();
        }
    }

    private Map<String, Boolean> kyc(Object raw) {
        try {
            return json.readValue(raw == null ? "{}" : raw.toString(), new TypeReference<>() { });
        } catch (Exception e) {
            return new LinkedHashMap<>();
        }
    }

    private String write(Object o) {
        try {
            return json.writeValueAsString(o);
        } catch (Exception e) {
            throw new IllegalStateException(e);
        }
    }

    private String actor() {
        UUID a = TenantContext.currentUserIdOrNull();
        var n = a == null ? List.<String>of() : jdbc.queryForList("SELECT full_name FROM users WHERE id = ?", String.class, a);
        return n.isEmpty() ? "Owleo staff" : n.get(0);
    }

    private void log(UUID id, String text) {
        jdbc.update("INSERT INTO hq_provider_log (provider_id, actor_name, text) VALUES (?, ?, ?)", id, actor(), text);
    }

    /** Performance figures per provider, from the jobs recorded for them. */
    private record Perf(int done, int cancelled, int upcoming, double rating, double completion, double onTime, double repeat, int disputes, BigDecimal value) {
    }

    private Map<UUID, Perf> perf() {
        Map<UUID, List<Map<String, Object>>> by = new HashMap<>();
        for (var j : jdbc.queryForList("SELECT provider_id, academy_id, status, rating, late, issue, amount FROM hq_provider_jobs")) {
            by.computeIfAbsent((UUID) j.get("provider_id"), k -> new ArrayList<>()).add(j);
        }
        Map<UUID, Perf> out = new HashMap<>();
        by.forEach((pid, jobs) -> {
            var done = jobs.stream().filter(j -> "DONE".equals(j.get("status"))).toList();
            int canc = (int) jobs.stream().filter(j -> "CANCELLED".equals(j.get("status"))).count();
            int up = (int) jobs.stream().filter(j -> "UPCOMING".equals(j.get("status"))).count();
            var rated = done.stream().filter(j -> j.get("rating") != null).toList();
            double rating = rated.isEmpty() ? 0 : rated.stream().mapToInt(j -> ((Number) j.get("rating")).intValue()).average().orElse(0);
            double completion = done.size() + canc == 0 ? 0 : done.size() * 100.0 / (done.size() + canc);
            double onTime = done.isEmpty() ? 0 : (1 - done.stream().filter(j -> Boolean.TRUE.equals(j.get("late"))).count() / (double) done.size()) * 100;
            Map<Object, Long> perAcademy = new HashMap<>();
            done.forEach(j -> perAcademy.merge(j.get("academy_id"), 1L, Long::sum));
            double repeat = perAcademy.isEmpty() ? 0 : perAcademy.values().stream().filter(x -> x > 1).count() * 100.0 / perAcademy.size();
            int disputes = (int) done.stream().filter(j -> Boolean.TRUE.equals(j.get("issue"))).count();
            BigDecimal value = done.stream().map(j -> (BigDecimal) j.get("amount")).reduce(BigDecimal.ZERO, BigDecimal::add);
            out.put(pid, new Perf(done.size(), canc, up, rating, completion, onTime, repeat, disputes, value));
        });
        return out;
    }

    private static List<String> flags(String status, Perf p) {
        List<String> f = new ArrayList<>();
        if (!"LIVE".equals(status) || p == null) return f;
        if (p.rating() > 0 && p.rating() < 4) f.add(String.format("Rating %.1f", p.rating()));
        if (p.done() > 0 && p.onTime() < 85) f.add("On time " + Math.round(p.onTime()) + "%");
        if (p.done() + p.cancelled() > 0 && p.completion() < 90) f.add("Cancels " + Math.round(100 - p.completion()) + "%");
        if (p.disputes() >= 3) f.add(p.disputes() + " complaints");
        return f;
    }

    private Map<String, Object> perfMap(Perf p) {
        Map<String, Object> m = new LinkedHashMap<>();
        if (p == null) p = new Perf(0, 0, 0, 0, 0, 0, 0, 0, BigDecimal.ZERO);
        m.put("done", p.done());
        m.put("cancelled", p.cancelled());
        m.put("upcoming", p.upcoming());
        m.put("rating", p.rating() == 0 ? null : Math.round(p.rating() * 10) / 10.0);
        m.put("completion", Math.round(p.completion()));
        m.put("onTime", Math.round(p.onTime()));
        m.put("repeat", Math.round(p.repeat()));
        m.put("complaints", p.disputes());
        m.put("value", p.value());
        return m;
    }

    private Map<String, Map<String, Object>> typeMap() {
        Map<String, Map<String, Object>> out = new LinkedHashMap<>();
        for (var t : jdbc.queryForList("SELECT code, name, icon, tone, active FROM hq_provider_types ORDER BY name")) out.put((String) t.get("code"), t);
        return out;
    }

    private Map<String, Object> card(Map<String, Object> r, Map<UUID, Perf> perf, Map<String, Map<String, Object>> types) {
        UUID id = (UUID) r.get("id");
        String status = (String) r.get("status");
        List<String> codes = List.of(((String) r.get("types")).split(","));
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("id", id);
        m.put("ref", ref(((Number) r.get("seq")).longValue()));
        m.put("name", r.get("name"));
        m.put("person", r.get("person"));
        m.put("city", r.get("city"));
        m.put("status", status.toLowerCase());
        m.put("types", codes.stream().map(c -> types.getOrDefault(c, Map.of("code", c, "name", c, "icon", "users", "tone", "mute"))).toList());
        m.put("price", r.get("price"));
        m.put("unit", r.get("unit"));
        var links = links(r.get("links"));
        m.put("linksChecked", links.stream().filter(l -> Boolean.TRUE.equals(l.get("ok"))).count());
        m.put("linksTotal", links.size());
        Perf p = perf.get(id);
        m.put("perf", perfMap(p));
        m.put("flags", flags(status, p));
        return m;
    }

    // ---------------------------------------------------------------- lists

    public Map<String, Object> overview() {
        var perf = perf();
        var types = typeMap();
        var rows = jdbc.queryForList("SELECT * FROM hq_providers ORDER BY created_at DESC");
        int live = 0, pipe = 0, watch = 0;
        double ratingSum = 0;
        int rated = 0;
        List<Map<String, Object>> cards = new ArrayList<>();
        for (var r : rows) {
            String st = (String) r.get("status");
            if ("LIVE".equals(st)) live++;
            if (Set.of("APPLIED", "REVIEW", "VERIFY").contains(st)) pipe++;
            Perf p = perf.get((UUID) r.get("id"));
            if (!flags(st, p).isEmpty()) watch++;
            if ("LIVE".equals(st) && p != null && p.rating() > 0) {
                ratingSum += p.rating();
                rated++;
            }
            cards.add(card(r, perf, types));
        }
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("live", live);
        out.put("pipeline", pipe);
        out.put("watch", watch);
        out.put("openRequests", jdbc.queryForObject("SELECT count(*) FROM hq_provider_requests WHERE status = 'OPEN'", Integer.class));
        out.put("avgRating", rated == 0 ? null : Math.round(ratingSum / rated * 10) / 10.0);
        out.put("providers", cards);
        out.put("types", typeList(rows, types));
        return out;
    }

    private List<Map<String, Object>> typeList(List<Map<String, Object>> providers, Map<String, Map<String, Object>> types) {
        List<Map<String, Object>> out = new ArrayList<>();
        types.forEach((code, t) -> {
            Map<String, Object> m = new LinkedHashMap<>(t);
            m.put("live", providers.stream().filter(p -> "LIVE".equals(p.get("status")) && List.of(((String) p.get("types")).split(",")).contains(code)).count());
            m.put("applying", providers.stream().filter(p -> Set.of("APPLIED", "REVIEW", "VERIFY").contains(p.get("status")) && List.of(((String) p.get("types")).split(",")).contains(code)).count());
            out.add(m);
        });
        return out;
    }

    public Map<String, Object> detail(UUID id) {
        var rows = jdbc.queryForList("SELECT * FROM hq_providers WHERE id = ?", id);
        if (rows.isEmpty()) throw new ResourceNotFoundException("Provider not found");
        var r = rows.get(0);
        var perf = perf();
        var types = typeMap();
        Map<String, Object> m = card(r, perf, types);
        m.put("phone", r.get("phone"));
        m.put("email", r.get("email"));
        m.put("bio", r.get("bio"));
        m.put("years", r.get("exp_years"));
        m.put("appliedOn", r.get("applied_on"));
        m.put("services", List.of(((String) r.get("services")).split("\n")).stream().filter(s -> !s.isBlank()).toList());
        m.put("links", links(r.get("links")));
        Map<String, Boolean> k = kyc(r.get("kyc"));
        List<Map<String, Object>> checks = new ArrayList<>();
        for (String[] c : KYC) checks.add(Map.of("key", c[0], "label", c[1], "sub", c[2], "done", Boolean.TRUE.equals(k.get(c[0]))));
        m.put("kyc", checks);
        m.put("log", jdbc.queryForList("SELECT actor_name AS who, text AS x, at FROM hq_provider_log WHERE provider_id = ? ORDER BY at DESC", id));
        // Six months of jobs, oldest first, and the latest few.
        List<Map<String, Object>> months = new ArrayList<>();
        for (int i = 5; i >= 0; i--) {
            YearMonth ym = YearMonth.now().minusMonths(i);
            var row = jdbc.queryForList("""
                    SELECT count(*) FILTER (WHERE status = 'DONE') AS done, count(*) FILTER (WHERE status = 'CANCELLED') AS cancelled
                    FROM hq_provider_jobs WHERE provider_id = ? AND to_char(job_date, 'YYYY-MM') = ?""", id, ym.toString()).get(0);
            months.add(Map.of("month", ym.toString(), "done", row.get("done"), "cancelled", row.get("cancelled")));
        }
        m.put("months", months);
        m.put("jobs", jobsOf(id, 6));
        return m;
    }

    private List<Map<String, Object>> jobsOf(UUID providerId, int limit) {
        return jdbc.queryForList("""
                SELECT j.id, a.name AS academy, j.event_name AS event, j.job_date AS date, j.amount, lower(j.status) AS status, j.rating, j.late, j.issue
                FROM hq_provider_jobs j JOIN academies a ON a.id = j.academy_id WHERE j.provider_id = ? ORDER BY j.job_date DESC LIMIT ?""", providerId, limit);
    }

    // ---------------------------------------------------------------- onboarding and checks

    @Transactional
    public UUID create(Map<String, Object> b) {
        String name = str(b, "name"), person = str(b, "person"), phone = str(b, "phone").replaceAll("\\s", ""), email = str(b, "email"), city = str(b, "city");
        if (name.length() < 3) throw new BadRequestException("Enter the business or studio name.");
        if (person.length() < 2) throw new BadRequestException("Enter the contact person's name.");
        if (!MOBILE.matcher(phone).matches()) throw new BadRequestException("Enter a 10-digit mobile number.");
        if (!EMAIL.matcher(email).matches()) throw new BadRequestException("Enter a valid email address.");
        if (city.length() < 2) throw new BadRequestException("Choose the city.");
        var types = typeMap();
        List<String> codes = new ArrayList<>();
        if (b.get("types") instanceof List<?> l) for (Object o : l) if (types.containsKey(String.valueOf(o))) codes.add(String.valueOf(o));
        if (codes.isEmpty()) throw new BadRequestException("Choose at least one thing they offer.");
        BigDecimal price;
        try {
            price = new BigDecimal(str(b, "price"));
        } catch (Exception e) {
            throw new BadRequestException("Enter the starting price.");
        }
        if (price.signum() < 0) throw new BadRequestException("The price cannot be negative.");
        String unit = str(b, "unit").isEmpty() ? "per event" : str(b, "unit");
        List<Map<String, Object>> links = new ArrayList<>();
        if (b.get("links") instanceof List<?> l) {
            for (Object o : l) {
                String u = String.valueOf(o).trim();
                if (u.isEmpty() || "null".equals(u)) continue;
                if (!URL.matcher(u).matches()) throw new BadRequestException("Links must start with https://: " + u);
                Map<String, Object> x = new LinkedHashMap<>();
                x.put("u", u);
                x.put("ok", null);
                links.add(x);
            }
        }
        if (links.isEmpty()) throw new BadRequestException("Add at least one portfolio link.");
        int years = b.get("years") instanceof Number n ? n.intValue() : (str(b, "years").isEmpty() ? 0 : Integer.parseInt(str(b, "years")));
        if (jdbc.queryForObject("SELECT count(*) FROM hq_providers WHERE lower(email) = lower(?) AND status <> 'REJECTED'", Integer.class, email) > 0) throw new ConflictException("A provider with this email already exists.");
        UUID id = UUID.randomUUID();
        jdbc.update("""
                INSERT INTO hq_providers (id, name, person, phone, email, city, types, price, unit, services, bio, exp_years, links)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
                id, name, person, phone, email, city, String.join(",", codes), price, unit, clip(str(b, "services"), 800), clip(str(b, "bio"), 500), Math.max(0, years), write(links));
        log(id, "Added as an applicant");
        audit.log("providers", "Added service provider " + name);
        return id;
    }

    private Map<String, Object> row(UUID id) {
        var rows = jdbc.queryForList("SELECT * FROM hq_providers WHERE id = ?", id);
        if (rows.isEmpty()) throw new ResourceNotFoundException("Provider not found");
        return rows.get(0);
    }

    @Transactional
    public void setLink(UUID id, int index, Boolean ok) {
        var r = row(id);
        var ls = links(r.get("links"));
        if (index < 0 || index >= ls.size()) throw new BadRequestException("Unknown link.");
        ls.get(index).put("ok", ok);
        jdbc.update("UPDATE hq_providers SET links = ? WHERE id = ?", write(ls), id);
        log(id, (ok == null ? "Reset " : Boolean.TRUE.equals(ok) ? "Confirmed " : "Marked broken: ") + ls.get(index).get("u"));
    }

    @Transactional
    public void setKyc(UUID id, String key, boolean done) {
        var r = row(id);
        if ("REJECTED".equals(r.get("status"))) throw new BadRequestException("This application was rejected.");
        if (KYC.stream().noneMatch(c -> c[0].equals(key))) throw new BadRequestException("Unknown check.");
        var k = kyc(r.get("kyc"));
        k.put(key, done);
        jdbc.update("UPDATE hq_providers SET kyc = ? WHERE id = ?", write(k), id);
    }

    @Transactional
    public void step(UUID id, String to) {
        var r = row(id);
        String from = (String) r.get("status");
        boolean ok = switch (to) {
            case "review" -> "APPLIED".equals(from);
            case "verify" -> "REVIEW".equals(from);
            case "live" -> "VERIFY".equals(from) || "SUSPENDED".equals(from);
            case "applied" -> "REJECTED".equals(from);
            default -> false;
        };
        if (!ok) throw new BadRequestException("That step is not available from here.");
        if ("live".equals(to) && "VERIFY".equals(from)) {
            var k = kyc(r.get("kyc"));
            if (!Boolean.TRUE.equals(k.get("id")) || !Boolean.TRUE.equals(k.get("call"))) throw new BadRequestException("Tick ID proof seen and the verification call first.");
            if (links(r.get("links")).stream().noneMatch(l -> Boolean.TRUE.equals(l.get("ok")))) throw new BadRequestException("At least one portfolio link must be confirmed as working.");
        }
        jdbc.update("UPDATE hq_providers SET status = ? WHERE id = ?", to.toUpperCase(), id);
        log(id, switch (to) { case "review" -> "Started checking links"; case "verify" -> "Links are fine. Verifying identity"; case "live" -> "SUSPENDED".equals(from) ? "Reinstated" : "Approved. Live now"; default -> "Reopened the application"; });
        audit.log("providers", "Provider " + r.get("name") + ": " + to);
    }

    @Transactional
    public void stop(UUID id, String kind, String reason) {
        var r = row(id);
        String from = (String) r.get("status");
        if (reason == null || reason.trim().length() < 3) throw new BadRequestException("Give a reason.");
        if ("suspended".equals(kind)) {
            if (!"LIVE".equals(from)) throw new BadRequestException("Only a live provider can be suspended.");
            jdbc.update("UPDATE hq_providers SET status = 'SUSPENDED' WHERE id = ?", id);
            log(id, "Suspended: " + reason.trim());
        } else {
            if (!Set.of("APPLIED", "REVIEW", "VERIFY").contains(from)) throw new BadRequestException("Only an applicant can be rejected.");
            jdbc.update("UPDATE hq_providers SET status = 'REJECTED' WHERE id = ?", id);
            log(id, "Rejected: " + reason.trim());
        }
        audit.log("providers", ("suspended".equals(kind) ? "Suspended provider " : "Rejected provider ") + r.get("name"));
    }

    @Transactional
    public void warn(UUID id, String message) {
        var r = row(id);
        if (message == null || message.trim().length() < 5) throw new BadRequestException("Write the warning.");
        log(id, "Warning sent: " + message.trim());
        audit.log("providers", "Warned provider " + r.get("name"));
    }

    // ---------------------------------------------------------------- types

    @Transactional
    public void addType(String name) {
        String n = name == null ? "" : name.trim();
        if (n.length() < 3) throw new BadRequestException("Give the type a name of at least 3 letters.");
        if (jdbc.queryForObject("SELECT count(*) FROM hq_provider_types WHERE lower(name) = lower(?)", Integer.class, n) > 0) throw new ConflictException("This type already exists.");
        String code = n.toLowerCase().replaceAll("[^a-z0-9]", "");
        code = code.substring(0, Math.min(20, code.length()));
        if (jdbc.queryForObject("SELECT count(*) FROM hq_provider_types WHERE code = ?", Integer.class, code) > 0) code = code.substring(0, Math.min(17, code.length())) + (int) (Math.random() * 900 + 100);
        jdbc.update("INSERT INTO hq_provider_types (code, name, icon, tone) VALUES (?, ?, 'spark', 'primary')", code, n);
        audit.log("providers", "Added service type " + n);
    }

    @Transactional
    public void setTypeActive(String code, boolean active) {
        if (jdbc.update("UPDATE hq_provider_types SET active = ? WHERE code = ?", active, code) == 0) throw new ResourceNotFoundException("Type not found");
        audit.log("providers", (active ? "Showed" : "Hid") + " service type " + code);
    }

    // ---------------------------------------------------------------- requests

    public List<Map<String, Object>> requests(String filter) {
        var types = typeMap();
        var names = new HashMap<UUID, String>();
        jdbc.queryForList("SELECT id, name FROM hq_providers").forEach(p -> names.put((UUID) p.get("id"), (String) p.get("name")));
        List<Map<String, Object>> out = new ArrayList<>();
        for (var r : jdbc.queryForList("""
                SELECT q.*, a.name AS academy, a.city FROM hq_provider_requests q JOIN academies a ON a.id = q.academy_id ORDER BY q.created_at DESC""")) {
            String st = ((String) r.get("status")).toLowerCase();
            boolean match = switch (filter == null ? "open" : filter) {
                case "open" -> Set.of("open", "matched", "quoted").contains(st);
                case "all" -> true;
                default -> st.equals(filter);
            };
            if (!match) continue;
            UUID id = (UUID) r.get("id");
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("id", id);
            m.put("ref", "RQ-" + (500 + ((Number) r.get("seq")).longValue()));
            m.put("academyId", r.get("academy_id"));
            m.put("academy", r.get("academy"));
            m.put("city", r.get("city"));
            m.put("type", types.getOrDefault((String) r.get("type_code"), Map.of("name", r.get("type_code"))).get("name"));
            m.put("typeCode", r.get("type_code"));
            m.put("event", r.get("event_name"));
            m.put("date", r.get("event_date"));
            m.put("budget", r.get("budget"));
            m.put("status", st);
            List<Map<String, Object>> sent = new ArrayList<>();
            jdbc.queryForList("SELECT provider_id FROM hq_provider_request_sent WHERE request_id = ? ORDER BY sent_at", id).forEach(s -> sent.add(Map.of("id", s.get("provider_id"), "name", names.getOrDefault((UUID) s.get("provider_id"), "?"))));
            m.put("sent", sent);
            List<Map<String, Object>> quotes = new ArrayList<>();
            try {
                List<Map<String, Object>> qs = json.readValue((String) r.get("quotes"), new TypeReference<>() { });
                for (var q : qs) quotes.add(Map.of("providerId", q.get("p"), "provider", names.getOrDefault(UUID.fromString((String) q.get("p")), "?"), "amount", q.get("amt")));
            } catch (Exception ignored) {
                // no quotes
            }
            m.put("quotes", quotes);
            m.put("hired", r.get("hired_id") == null ? null : names.get((UUID) r.get("hired_id")));
            out.add(m);
        }
        return out;
    }

    @Transactional
    public UUID createRequest(UUID academy, String type, String event, String date, String budget) {
        if (jdbc.queryForObject("SELECT count(*) FROM academies WHERE id = ? AND closed_at IS NULL", Integer.class, academy) == 0) throw new BadRequestException("Choose an academy.");
        if (jdbc.queryForObject("SELECT count(*) FROM hq_provider_types WHERE code = ? AND active", Integer.class, type) == 0) throw new BadRequestException("Choose the kind of service.");
        if (event == null || event.trim().length() < 3) throw new BadRequestException("Name the event.");
        LocalDate d;
        try {
            d = LocalDate.parse(date);
        } catch (Exception e) {
            throw new BadRequestException("Choose the event date.");
        }
        BigDecimal b;
        try {
            b = new BigDecimal(budget);
        } catch (Exception e) {
            throw new BadRequestException("Enter the budget.");
        }
        if (b.signum() <= 0) throw new BadRequestException("Enter a budget above zero.");
        UUID id = UUID.randomUUID();
        jdbc.update("INSERT INTO hq_provider_requests (id, academy_id, type_code, event_name, event_date, budget) VALUES (?, ?, ?, ?, ?, ?)", id, academy, type, event.trim(), d, b);
        audit.log("providers", academy, "Logged a " + type + " request for " + event.trim());
        return id;
    }

    /** Live providers of the requested type, same city first, best rated first. */
    public List<Map<String, Object>> suggestions(UUID requestId) {
        var q = jdbc.queryForList("SELECT q.type_code, a.city FROM hq_provider_requests q JOIN academies a ON a.id = q.academy_id WHERE q.id = ?", requestId);
        if (q.isEmpty()) throw new ResourceNotFoundException("Request not found");
        String type = (String) q.get(0).get("type_code"), city = (String) q.get(0).get("city");
        var perf = perf();
        var sent = new java.util.HashSet<>(jdbc.queryForList("SELECT provider_id FROM hq_provider_request_sent WHERE request_id = ?", UUID.class, requestId));
        List<Map<String, Object>> out = new ArrayList<>();
        for (var p : jdbc.queryForList("SELECT * FROM hq_providers WHERE status = 'LIVE'")) {
            if (!List.of(((String) p.get("types")).split(",")).contains(type)) continue;
            Perf pf = perf.get((UUID) p.get("id"));
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("id", p.get("id"));
            m.put("name", p.get("name"));
            m.put("city", p.get("city"));
            m.put("sameCity", city != null && city.equalsIgnoreCase((String) p.get("city")));
            m.put("rating", pf == null || pf.rating() == 0 ? null : Math.round(pf.rating() * 10) / 10.0);
            m.put("price", p.get("price"));
            m.put("unit", p.get("unit"));
            m.put("sent", sent.contains((UUID) p.get("id")));
            out.add(m);
        }
        out.sort(Comparator.comparing((Map<String, Object> m) -> !Boolean.TRUE.equals(m.get("sameCity"))).thenComparing(m -> -(m.get("rating") == null ? 0.0 : (Double) m.get("rating"))));
        return out;
    }

    private Map<String, Object> request(UUID id) {
        var rows = jdbc.queryForList("SELECT * FROM hq_provider_requests WHERE id = ?", id);
        if (rows.isEmpty()) throw new ResourceNotFoundException("Request not found");
        return rows.get(0);
    }

    @Transactional
    public void send(UUID requestId, List<UUID> providers) {
        var q = request(requestId);
        if (!Set.of("OPEN", "MATCHED", "QUOTED").contains(q.get("status"))) throw new BadRequestException("This request is closed.");
        if (providers == null || providers.isEmpty()) throw new BadRequestException("Pick at least one provider.");
        for (UUID p : providers) {
            if (jdbc.queryForObject("SELECT count(*) FROM hq_providers WHERE id = ? AND status = 'LIVE'", Integer.class, p) == 0) throw new BadRequestException("Only live providers can be sent a request.");
            jdbc.update("INSERT INTO hq_provider_request_sent (request_id, provider_id) VALUES (?, ?) ON CONFLICT DO NOTHING", requestId, p);
        }
        if ("OPEN".equals(q.get("status"))) jdbc.update("UPDATE hq_provider_requests SET status = 'MATCHED' WHERE id = ?", requestId);
        audit.log("providers", (UUID) q.get("academy_id"), "Sent request for " + q.get("event_name") + " to " + providers.size() + " provider(s)");
    }

    @Transactional
    public void quote(UUID requestId, UUID provider, BigDecimal amount) {
        var q = request(requestId);
        if (!Set.of("MATCHED", "QUOTED").contains(q.get("status"))) throw new BadRequestException("Send the request to providers first.");
        if (amount == null || amount.signum() <= 0) throw new BadRequestException("Enter the quote amount.");
        if (jdbc.queryForObject("SELECT count(*) FROM hq_provider_request_sent WHERE request_id = ? AND provider_id = ?", Integer.class, requestId, provider) == 0) throw new BadRequestException("This provider was not sent the request.");
        List<Map<String, Object>> qs;
        try {
            qs = json.readValue((String) q.get("quotes"), new TypeReference<>() { });
        } catch (Exception e) {
            qs = new ArrayList<>();
        }
        qs.removeIf(x -> provider.toString().equals(x.get("p")));
        qs.add(Map.of("p", provider.toString(), "amt", amount));
        jdbc.update("UPDATE hq_provider_requests SET quotes = ?, status = 'QUOTED' WHERE id = ?", write(qs), requestId);
    }

    @Transactional
    public void hire(UUID requestId, UUID provider) {
        var q = request(requestId);
        if (!Set.of("MATCHED", "QUOTED").contains(q.get("status"))) throw new BadRequestException("This request cannot be hired against.");
        if (jdbc.queryForObject("SELECT count(*) FROM hq_provider_request_sent WHERE request_id = ? AND provider_id = ?", Integer.class, requestId, provider) == 0) throw new BadRequestException("This provider was not sent the request.");
        BigDecimal amount = (BigDecimal) q.get("budget");
        try {
            List<Map<String, Object>> qs = json.readValue((String) q.get("quotes"), new TypeReference<>() { });
            for (var x : qs) if (provider.toString().equals(x.get("p"))) amount = new BigDecimal(x.get("amt").toString());
        } catch (Exception ignored) {
            // use the budget
        }
        jdbc.update("UPDATE hq_provider_requests SET status = 'HIRED', hired_id = ? WHERE id = ?", provider, requestId);
        jdbc.update("""
                INSERT INTO hq_provider_jobs (provider_id, academy_id, request_id, event_name, job_date, amount) VALUES (?, ?, ?, ?, ?, ?)""",
                provider, q.get("academy_id"), requestId, q.get("event_name"), q.get("event_date"), amount);
        log(provider, "Hired for " + q.get("event_name"));
        audit.log("providers", (UUID) q.get("academy_id"), "Hired a provider for " + q.get("event_name"));
    }

    @Transactional
    public void closeRequest(UUID requestId) {
        var q = request(requestId);
        if (!Set.of("OPEN", "MATCHED", "QUOTED").contains(q.get("status"))) throw new BadRequestException("This request is already finished.");
        jdbc.update("UPDATE hq_provider_requests SET status = 'CLOSED' WHERE id = ?", requestId);
        audit.log("providers", (UUID) q.get("academy_id"), "Closed the request for " + q.get("event_name"));
    }

    @Transactional
    public void recordOutcome(UUID jobId, String status, Integer rating, boolean late, boolean issue) {
        var j = jdbc.queryForList("SELECT provider_id, status FROM hq_provider_jobs WHERE id = ?", jobId);
        if (j.isEmpty()) throw new ResourceNotFoundException("Job not found");
        if (!"UPCOMING".equals(j.get(0).get("status"))) throw new BadRequestException("This job already has an outcome.");
        if ("done".equals(status)) {
            if (rating == null || rating < 1 || rating > 5) throw new BadRequestException("Give the academy's rating, 1 to 5.");
            jdbc.update("UPDATE hq_provider_jobs SET status = 'DONE', rating = ?, late = ?, issue = ? WHERE id = ?", rating, late, issue, jobId);
        } else if ("cancelled".equals(status)) {
            jdbc.update("UPDATE hq_provider_jobs SET status = 'CANCELLED' WHERE id = ?", jobId);
        } else {
            throw new BadRequestException("Choose done or cancelled.");
        }
        log((UUID) j.get(0).get("provider_id"), "Job recorded as " + status);
    }

    // ---------------------------------------------------------------- performance

    public Map<String, Object> performance() {
        var perf = perf();
        var types = typeMap();
        List<Map<String, Object>> months = new ArrayList<>();
        for (int i = 5; i >= 0; i--) {
            YearMonth ym = YearMonth.now().minusMonths(i);
            var row = jdbc.queryForList("""
                    SELECT count(*) FILTER (WHERE status = 'DONE') AS done, count(*) FILTER (WHERE status = 'CANCELLED') AS cancelled,
                           avg(rating) FILTER (WHERE status = 'DONE' AND rating IS NOT NULL) AS rating
                    FROM hq_provider_jobs WHERE to_char(job_date, 'YYYY-MM') = ?""", ym.toString()).get(0);
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("month", ym.toString());
            m.put("done", row.get("done"));
            m.put("cancelled", row.get("cancelled"));
            m.put("rating", row.get("rating") == null ? 0 : Math.round(((Number) row.get("rating")).doubleValue() * 100) / 100.0);
            months.add(m);
        }
        List<Map<String, Object>> watch = new ArrayList<>(), ranked = new ArrayList<>();
        Map<String, double[]> byType = new LinkedHashMap<>();
        for (var r : jdbc.queryForList("SELECT * FROM hq_providers WHERE status IN ('LIVE', 'SUSPENDED')")) {
            UUID id = (UUID) r.get("id");
            Perf p = perf.get(id);
            String st = (String) r.get("status");
            var f = flags(st, p);
            Map<String, Object> c = card(r, perf, types);
            if (!f.isEmpty()) watch.add(c);
            if ("LIVE".equals(st) && p != null && p.rating() > 0) ranked.add(c);
            if ("LIVE".equals(st)) {
                for (String code : ((String) r.get("types")).split(",")) {
                    double[] a = byType.computeIfAbsent(code, k -> new double[4]);   // providers, jobs, rating sum, rated providers
                    a[0]++;
                    if (p != null) {
                        a[1] += p.done();
                        if (p.rating() > 0) {
                            a[2] += p.rating();
                            a[3]++;
                        }
                    }
                }
            }
        }
        ranked.sort((a, b) -> Double.compare(rating(b), rating(a)));
        List<Map<String, Object>> typeRows = new ArrayList<>();
        byType.forEach((code, a) -> {
            Map<String, Object> m = new LinkedHashMap<>(types.getOrDefault(code, Map.of("name", code, "icon", "users", "tone", "mute")));
            m.put("providers", (int) a[0]);
            m.put("jobs", (int) a[1]);
            m.put("rating", a[3] == 0 ? null : Math.round(a[2] / a[3] * 10) / 10.0);
            typeRows.add(m);
        });
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("months", months);
        out.put("watch", watch);
        out.put("best", ranked.stream().limit(5).toList());
        out.put("byType", typeRows);
        return out;
    }

    @SuppressWarnings("unchecked")
    private static double rating(Map<String, Object> card) {
        Object r = ((Map<String, Object>) card.get("perf")).get("rating");
        return r == null ? 0 : ((Number) r).doubleValue();
    }

    public List<Map<String, Object>> typeOptions() {
        List<Map<String, Object>> out = new ArrayList<>();
        typeMap().forEach((code, t) -> {
            if (Boolean.TRUE.equals(t.get("active"))) out.add(t);
        });
        return out;
    }

    private static String clip(String s, int max) {
        return s.length() > max ? s.substring(0, max) : s;
    }

    private static String str(Map<String, Object> b, String k) {
        Object v = b.get(k);
        return v == null ? "" : v.toString().trim();
    }
}
