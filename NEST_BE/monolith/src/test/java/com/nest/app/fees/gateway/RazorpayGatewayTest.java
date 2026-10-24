package com.nest.app.fees.gateway;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;

import java.nio.charset.StandardCharsets;

import static org.assertj.core.api.Assertions.assertThat;

class RazorpayGatewayTest {

    private final RazorpayGateway gateway =
            new RazorpayGateway("rzp_test_abc", "key-secret", "hook-secret", new ObjectMapper());

    @Test
    void aCheckoutSignatureMadeWithTheKeySecretVerifies() {
        String sig = RazorpayGateway.hmacHex("key-secret", "order_1|pay_1".getBytes(StandardCharsets.UTF_8));

        assertThat(gateway.verifyCheckoutSignature("order_1", "pay_1", sig)).isTrue();
    }

    @Test
    void aSignatureForADifferentPaymentOrOrderIsRefused() {
        String sig = RazorpayGateway.hmacHex("key-secret", "order_1|pay_1".getBytes(StandardCharsets.UTF_8));

        assertThat(gateway.verifyCheckoutSignature("order_1", "pay_2", sig)).isFalse();
        assertThat(gateway.verifyCheckoutSignature("order_2", "pay_1", sig)).isFalse();
        assertThat(gateway.verifyCheckoutSignature("order_1", "pay_1", "deadbeef")).isFalse();
        assertThat(gateway.verifyCheckoutSignature("order_1", "pay_1", null)).isFalse();
    }

    @Test
    void theWebhookSecretAndTheKeySecretAreNotInterchangeable() {
        byte[] body = "{\"event\":\"payment.captured\"}".getBytes(StandardCharsets.UTF_8);

        assertThat(gateway.verifyWebhookSignature(body, RazorpayGateway.hmacHex("hook-secret", body))).isTrue();
        assertThat(gateway.verifyWebhookSignature(body, RazorpayGateway.hmacHex("key-secret", body))).isFalse();
    }

    @Test
    void aWebhookWhoseBodyWasTamperedWithIsRefused() {
        byte[] body = "{\"amount\":100}".getBytes(StandardCharsets.UTF_8);
        String sig = RazorpayGateway.hmacHex("hook-secret", body);

        assertThat(gateway.verifyWebhookSignature("{\"amount\":1}".getBytes(StandardCharsets.UTF_8), sig)).isFalse();
    }

    @Test
    void withoutCredentialsNothingVerifiesAndNothingIsConfigured() {
        var bare = new RazorpayGateway("", "", "", new ObjectMapper());

        assertThat(bare.configured()).isFalse();
        assertThat(bare.webhookConfigured()).isFalse();
        // Even a perfectly signed body is refused when no webhook secret is configured.
        assertThat(bare.verifyWebhookSignature(new byte[0], RazorpayGateway.hmacHex("any", new byte[0]))).isFalse();
    }
}
