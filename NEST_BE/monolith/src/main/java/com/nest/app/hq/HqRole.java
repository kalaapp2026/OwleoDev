package com.nest.app.hq;

import java.util.Set;

/**
 * The four kinds of HQ staff, and which console modules each can open. This is the server's copy
 * of the table in the console prototype; the web app mirrors it only to lock tiles. The module
 * ids are the console's route names ({@code academies}, {@code finance}, ...).
 *
 * <p>Writing - changing an academy, a user, a batch - is limited to SUPER and OPS. FINANCE and
 * SUPPORT can read what their modules show and act inside their own area (a support agent
 * replies to a ticket), which is why "write" is a separate question from "can open".
 */
public enum HqRole {
    SUPER("Super admin", Set.of("*")),
    OPS("Operations admin", Set.of("artists", "events", "support", "overview", "users", "academies",
            "onboarding", "approvals", "courses", "exits", "reports", "alerts", "students")),
    FINANCE("Finance admin", Set.of("support", "overview", "finance", "plans", "growth", "approvals",
            "reports", "academies", "marketing", "collections")),
    SUPPORT("Support admin", Set.of("artists", "events", "support", "overview", "users", "exits",
            "alerts", "students", "courses"));

    private final String label;
    private final Set<String> modules;

    HqRole(String label, Set<String> modules) {
        this.label = label;
        this.modules = modules;
    }

    public String label() {
        return label;
    }

    public Set<String> modules() {
        return modules;
    }

    public boolean canOpen(String module) {
        return modules.contains("*") || modules.contains(module);
    }

    public boolean canWrite() {
        return this == SUPER || this == OPS;
    }

    public boolean canExport() {
        return this == SUPER || this == OPS || this == FINANCE;
    }

    /** A missing or unknown value means SUPER: the seeded super admin has no hq_role yet. */
    public static HqRole of(String value) {
        if (value == null) {
            return SUPER;
        }
        try {
            return valueOf(value);
        } catch (IllegalArgumentException e) {
            return SUPER;
        }
    }
}
