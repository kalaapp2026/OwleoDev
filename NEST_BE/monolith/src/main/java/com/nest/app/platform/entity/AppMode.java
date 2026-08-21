package com.nest.app.platform.entity;

/**
 * Which half of the app people get, set platform-wide by the Super Admin.
 *
 * <p>Rollout is ERP-first: an academy being onboarded shouldn't be shown a Social side that isn't
 * ready for them yet. The two "_ONLY" values hide the other half completely - including the nav's
 * centre toggle, so there's nothing to discover and nothing to explain.
 *
 * <p>Deliberately one enum rather than two independent flags ("which opens first" and "restrict to
 * one"), because two flags allow contradictory combinations - "only ERP, but open Social first" -
 * that have no sensible behaviour.
 */
public enum AppMode {

    /** Both halves available; the app opens on ERP. */
    ERP_FIRST,

    /** Both halves available; the app opens on Social. */
    SOCIAL_FIRST,

    /** Social is hidden entirely and the toggle disappears. */
    ERP_ONLY,

    /** ERP is hidden entirely and the toggle disappears. */
    SOCIAL_ONLY;

    public boolean allowsErp() {
        return this != SOCIAL_ONLY;
    }

    public boolean allowsSocial() {
        return this != ERP_ONLY;
    }

    /** True when the person can move between the two halves at all - i.e. whether the nav's centre
     * toggle does anything. */
    public boolean allowsBoth() {
        return allowsErp() && allowsSocial();
    }

    public boolean startsOnErp() {
        return this == ERP_FIRST || this == ERP_ONLY;
    }
}
