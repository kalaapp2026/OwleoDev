package com.nest.common.crypto;

import org.springframework.boot.context.properties.ConfigurationProperties;

@ConfigurationProperties(prefix = "nest.crypto")
public class CryptoProperties {

    /**
     * Base64-encoded 256-bit AES key. MUST be overridden per-environment via NEST_CRYPTO_KEY -
     * the default is dev-only and well-known, so it provides zero real protection.
     */
    private String key = "ZGV2LW9ubHktY2hhbmdlLW1lLTMyLWJ5dGVzLWtleSE=";

    /**
     * Base64-encoded key used for deterministic HMAC lookups (see {@link PiiHasher}). Deliberately
     * a separate property from {@link #key} - production should use a distinct secret here so a
     * compromise of one purpose doesn't also compromise the other. Same dev-only caveat applies.
     */
    private String hmacKey = "ZGV2LW9ubHktaG1hYy1rZXktZGV2LW9ubHktMzJieQ=="; // NOTE: replace with a strong base64 secret via NEST_CRYPTO_HMAC_KEY

    public String getKey() {
        return key;
    }

    public void setKey(String key) {
        this.key = key;
    }

    public String getHmacKey() {
        return hmacKey;
    }

    public void setHmacKey(String hmacKey) {
        this.hmacKey = hmacKey;
    }
}
