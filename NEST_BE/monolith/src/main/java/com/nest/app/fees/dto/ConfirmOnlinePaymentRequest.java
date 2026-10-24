package com.nest.app.fees.dto;

import jakarta.validation.constraints.NotBlank;

/** The three values the gateway's checkout hands the browser once a payment goes through. */
public record ConfirmOnlinePaymentRequest(
        @NotBlank String orderId,
        @NotBlank String paymentId,
        @NotBlank String signature
) {
}
