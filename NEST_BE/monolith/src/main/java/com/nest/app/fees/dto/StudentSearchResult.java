package com.nest.app.fees.dto;

import java.util.UUID;

/**
 * A student matched by the fees landing's search box.
 *
 * <p>Deduplicated by person: the prototype searches every course/batch bucket and a student in two
 * courses would otherwise appear twice, which reads as two different people.</p>
 */
public record StudentSearchResult(
        UUID membershipId,
        String studentName,
        String context
) {
}
