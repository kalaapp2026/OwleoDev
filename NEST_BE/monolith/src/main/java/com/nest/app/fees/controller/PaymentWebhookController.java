package com.nest.app.fees.controller;

import com.nest.app.fees.service.OnlinePaymentService;
import io.swagger.v3.oas.annotations.Hidden;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

/**
 * Razorpay calling us. Public in {@code SecurityConfig} because Razorpay has no NEST login; the
 * request is authenticated by its HMAC signature instead, which {@link OnlinePaymentService} checks
 * against the RAW bytes - hence {@code byte[]} and not a parsed DTO.
 */
@RestController
@Hidden
public class PaymentWebhookController {

    private final OnlinePaymentService onlinePaymentService;

    public PaymentWebhookController(OnlinePaymentService onlinePaymentService) {
        this.onlinePaymentService = onlinePaymentService;
    }

    @PostMapping("/payments/razorpay/webhook")
    public ResponseEntity<Map<String, Object>> razorpay(
            @RequestBody byte[] rawBody,
            @RequestHeader(value = "X-Razorpay-Signature", required = false) String signature) {
        if (!onlinePaymentService.handleWebhook(rawBody, signature)) {
            return ResponseEntity.status(401).body(Map.of("error", "Invalid signature"));
        }
        return ResponseEntity.ok(Map.of("received", true));
    }
}
