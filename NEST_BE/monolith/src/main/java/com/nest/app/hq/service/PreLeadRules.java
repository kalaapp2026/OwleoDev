package com.nest.app.hq.service;

import java.util.Map;
import java.util.regex.Pattern;

/**
 * What a pre-lead needs: the academy's own details and nothing about an account. An academy HQ has
 * only heard of has no owner, plan or bank accounts to give yet, so none of those are asked for.
 *
 * <p>Required: a name, the type, the city and state, and at least one way to reach the academy.
 * Everything else about the address is optional - but anything given must be well formed, so a
 * typo does not follow the academy into the lead stage.
 */
final class PreLeadRules {

    private static final Pattern EMAIL = Pattern.compile("^\\S+@\\S+\\.\\S+$");
    private static final Pattern MOBILE = Pattern.compile("^[6-9]\\d{9}$");

    private PreLeadRules() {
    }

    /** The first problem with {@code b}, in the order the form asks, or null when it is fine. */
    static String problem(Map<String, Object> b) {
        String name = get(b, "name"), type = get(b, "type"), city = get(b, "city"), state = get(b, "state");
        String email = get(b, "aemail"), phone = get(b, "aphone"), a1 = get(b, "a1"), pin = get(b, "pin");

        if (name.length() < 3) return "Enter the academy name.";
        if (type.isEmpty() || type.length() > 20) return "Choose the academy type.";
        if (city.length() < 2) return "Enter the city.";
        if (state.length() < 2) return "Enter the state.";
        if (email.isEmpty() && phone.isEmpty()) return "Add the academy's phone or email so the team can reach them.";
        if (!email.isEmpty() && !EMAIL.matcher(email).matches()) return "Enter a valid academy email address.";
        if (!phone.isEmpty() && !MOBILE.matcher(phone).matches()) return "Enter the academy phone as a 10-digit mobile number.";
        if (!a1.isEmpty() && a1.length() < 3) return "Address line 1 needs a house number and street, or leave it empty.";
        if (!pin.isEmpty() && !pin.matches("^\\d{6}$")) return "Enter a 6-digit PIN code, or leave it empty.";
        return null;
    }

    private static String get(Map<String, Object> b, String key) {
        Object v = b.get(key);
        return v == null ? "" : v.toString().trim();
    }
}
