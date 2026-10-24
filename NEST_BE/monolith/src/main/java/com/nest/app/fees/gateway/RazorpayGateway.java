package com.nest.app.fees.gateway;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.nest.common.exception.UpstreamServiceException;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.security.MessageDigest;
import java.time.Duration;
import java.util.HexFormat;
import java.util.Map;

/**
 * The only class that talks to Razorpay. Plain HTTP against the Orders API rather than the vendor
 * SDK: three calls and two HMAC checks do not justify a dependency that pulls its own JSON and
 * HTTP stacks into a service that already has both.
 *
 * <p>It does nothing unless {@code nest.razorpay.key-id} and {@code key-secret} are set, so a
 * deployment without credentials simply has online payment off. The key id is public (the checkout
 * needs it in the browser); the key secret and webhook secret never leave this class.</p>
 */
@Component
public class RazorpayGateway {

    public static final String PROVIDER = "RAZORPAY";
    private static final String ORDERS_URL = "https://api.razorpay.com/v1/orders";

    private final String keyId;
    private final String keySecret;
    private final String webhookSecret;
    private final ObjectMapper mapper;
    private final HttpClient http = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(10)).build();

    public RazorpayGateway(@Value("${nest.razorpay.key-id:}") String keyId,
                           @Value("${nest.razorpay.key-secret:}") String keySecret,
                           @Value("${nest.razorpay.webhook-secret:}") String webhookSecret,
                           ObjectMapper mapper) {
        this.keyId = keyId == null ? "" : keyId.trim();
        this.keySecret = keySecret == null ? "" : keySecret.trim();
        this.webhookSecret = webhookSecret == null ? "" : webhookSecret.trim();
        this.mapper = mapper;
    }

    public boolean configured() {
        return !keyId.isEmpty() && !keySecret.isEmpty();
    }

    /** True when webhooks can be authenticated. Without it the webhook endpoint refuses everything. */
    public boolean webhookConfigured() {
        return !webhookSecret.isEmpty();
    }

    public String keyId() {
        return keyId;
    }

    /** Creates an order and returns Razorpay's id for it ({@code order_xxx}). */
    public String createOrder(long amountPaise, String currency, String receipt, Map<String, String> notes) {
        if (!configured()) {
            throw new IllegalStateException("Razorpay is not configured");
        }
        try {
            String body = mapper.writeValueAsString(Map.of(
                    "amount", amountPaise,
                    "currency", currency,
                    "receipt", receipt,
                    "notes", notes));
            HttpRequest request = HttpRequest.newBuilder(URI.create(ORDERS_URL))
                    .timeout(Duration.ofSeconds(20))
                    .header("Content-Type", "application/json")
                    .header("Authorization", "Basic " + java.util.Base64.getEncoder()
                            .encodeToString((keyId + ":" + keySecret).getBytes(StandardCharsets.UTF_8)))
                    .POST(HttpRequest.BodyPublishers.ofString(body))
                    .build();
            HttpResponse<String> response = http.send(request, HttpResponse.BodyHandlers.ofString());
            if (response.statusCode() / 100 != 2) {
                // The body is Razorpay's own error JSON; it never echoes our secret.
                throw new UpstreamServiceException("Razorpay refused the order (" + response.statusCode() + "): "
                        + errorDescription(response.body()));
            }
            JsonNode json = mapper.readTree(response.body());
            String id = json.path("id").asText("");
            if (id.isEmpty()) {
                throw new UpstreamServiceException("Razorpay returned no order id");
            }
            return id;
        } catch (IOException e) {
            throw new UpstreamServiceException("Could not reach Razorpay: " + e.getMessage());
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new UpstreamServiceException("Interrupted while contacting Razorpay");
        }
    }

    /**
     * The signature Checkout hands the browser after a payment: HMAC-SHA256 of
     * {@code order_id|payment_id} keyed with the key SECRET. A browser that never paid cannot
     * produce one, which is the whole reason the server checks it before settling anything.
     */
    public boolean verifyCheckoutSignature(String orderId, String paymentId, String signature) {
        if (!configured() || orderId == null || paymentId == null || signature == null) {
            return false;
        }
        return constantTimeEquals(hmacHex(keySecret, (orderId + "|" + paymentId).getBytes(StandardCharsets.UTF_8)), signature);
    }

    /** Razorpay signs the RAW webhook body with the webhook secret; parsing first would change the bytes. */
    public boolean verifyWebhookSignature(byte[] rawBody, String signature) {
        if (!webhookConfigured() || rawBody == null || signature == null) {
            return false;
        }
        return constantTimeEquals(hmacHex(webhookSecret, rawBody), signature);
    }

    private String errorDescription(String body) {
        try {
            return mapper.readTree(body).path("error").path("description").asText("unknown error");
        } catch (IOException e) {
            return "unknown error";
        }
    }

    static String hmacHex(String secret, byte[] data) {
        try {
            Mac mac = Mac.getInstance("HmacSHA256");
            mac.init(new SecretKeySpec(secret.getBytes(StandardCharsets.UTF_8), "HmacSHA256"));
            return HexFormat.of().formatHex(mac.doFinal(data));
        } catch (GeneralSecurityException e) {
            throw new IllegalStateException(e);
        }
    }

    private static boolean constantTimeEquals(String expected, String actual) {
        return MessageDigest.isEqual(expected.getBytes(StandardCharsets.UTF_8), actual.getBytes(StandardCharsets.UTF_8));
    }
}
