package com.nest.common.crypto;

import org.springframework.stereotype.Component;

import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import java.nio.charset.StandardCharsets;
import java.util.Base64;
import java.util.HexFormat;

/**
 * {@link PiiEncryptor} uses a random IV per call, so its output can never back a unique index or
 * an equality lookup - two encryptions of the same phone number produce different ciphertext.
 * This produces a deterministic HMAC-SHA256 digest instead, stored alongside the encrypted value
 * specifically so services can still do "does this phone number already exist" lookups (the crux
 * of PRD Section 7.4's existing-user detection) and enforce DB-level uniqueness, without storing
 * the PII itself in a searchable/reversible form.
 */
@Component
public class PiiHasher {

    private static final String HMAC_ALGORITHM = "HmacSHA256";

    private final SecretKeySpec hmacKey;

    public PiiHasher(CryptoProperties properties) {
        byte[] keyBytes = Base64.getDecoder().decode(properties.getHmacKey());
        this.hmacKey = new SecretKeySpec(keyBytes, HMAC_ALGORITHM);
    }

    public String hash(String value) {
        if (value == null) {
            return null;
        }
        try {
            Mac mac = Mac.getInstance(HMAC_ALGORITHM);
            mac.init(hmacKey);
            byte[] digest = mac.doFinal(normalise(value).getBytes(StandardCharsets.UTF_8));
            return HexFormat.of().formatHex(digest);
        } catch (Exception ex) {
            throw new IllegalStateException("Failed to hash PII field", ex);
        }
    }

    private String normalise(String value) {
        return value.trim().toLowerCase();
    }
}
