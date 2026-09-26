package com.nest.app.academy.dto;

/** Updates only the custom designation label - who is featured is changed via add/delete, not
 * this endpoint. */
public record UpdateFeaturedTrainerRequest(String designation) {
}
