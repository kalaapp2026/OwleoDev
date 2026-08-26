package com.nest.app.fees.dto;

/**
 * Why a payment was undone. Optional - an admin correcting a mis-tap shouldn't be forced to write
 * an essay - but recorded on the reversing row when given, since "why" is the one thing the
 * amounts alone can never show.
 */
public record ReverseFeeEntryRequest(String reason) {
}
