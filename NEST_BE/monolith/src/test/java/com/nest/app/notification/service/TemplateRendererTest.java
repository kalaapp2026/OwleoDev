package com.nest.app.notification.service;

import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;

class TemplateRendererTest {

    @Test
    void fillsPlaceholdersAndToleratesWhitespaceInsideBraces() {
        assertEquals("Hi Asha, 12 Oct",
                TemplateRenderer.render("Hi {{ name }}, {{date}}", Map.of("name", "Asha", "date", "12 Oct")));
    }

    @Test
    void missingValueRendersEmptyAndTidiesTheGap() {
        assertEquals("Class off.", TemplateRenderer.render("Class off. {{reason}}", Map.of()));
    }

    @Test
    void valuesWithRegexCharactersAreNotInterpreted() {
        assertEquals("Paid Rs $2,500", TemplateRenderer.render("Paid {{a}}", Map.of("a", "Rs $2,500")));
    }

    @Test
    void placeholderOrderIsFirstAppearanceAndDeduplicated() {
        assertEquals(List.of("b", "a", "c"), TemplateRenderer.placeholdersIn("{{b}} {{a}} {{b}} {{c}}"));
    }

    @Test
    void unknownPlaceholdersAreReported() {
        assertEquals(List.of("oops"), TemplateRenderer.unknownPlaceholders("{{a}} {{oops}}", List.of("a")));
    }
}
