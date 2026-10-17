package com.nest.app.notification.service;

import java.util.ArrayList;
import java.util.Collection;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/** Fills {@code {{placeholder}}} tokens. A token with no value renders as empty rather than leaking
 * the raw braces into someone's phone. */
public final class TemplateRenderer {

    private static final Pattern TOKEN = Pattern.compile("\\{\\{\\s*(\\w+)\\s*}}");

    private TemplateRenderer() {
    }

    public static String render(String template, Map<String, String> values) {
        Matcher m = TOKEN.matcher(template);
        StringBuilder out = new StringBuilder();
        while (m.find()) {
            String value = values.get(m.group(1));
            m.appendReplacement(out, Matcher.quoteReplacement(value == null ? "" : value));
        }
        m.appendTail(out);
        // A dropped trailing placeholder ("... {{reason}}") would leave dangling spaces.
        return out.toString().replaceAll("[ \\t]{2,}", " ").trim();
    }

    /** Distinct placeholder names in order of first appearance. This order is also the WhatsApp
     * variable order ({{1}}, {{2}}, ...), which is why it is stable and documented. */
    public static List<String> placeholdersIn(String template) {
        Set<String> names = new LinkedHashSet<>();
        Matcher m = TOKEN.matcher(template);
        while (m.find()) names.add(m.group(1));
        return new ArrayList<>(names);
    }

    /** Placeholders in {@code template} that are not in {@code allowed} - these would silently
     * render blank, so saving rejects them. */
    public static List<String> unknownPlaceholders(String template, Collection<String> allowed) {
        List<String> unknown = placeholdersIn(template);
        unknown.removeAll(allowed);
        return unknown;
    }
}
