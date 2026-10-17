package com.nest.app.notification.channel;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import io.jsonwebtoken.Jwts;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Component;
import org.springframework.util.LinkedMultiValueMap;
import org.springframework.util.MultiValueMap;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientResponseException;

import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.KeyFactory;
import java.security.PrivateKey;
import java.security.spec.PKCS8EncodedKeySpec;
import java.time.Instant;
import java.util.Base64;
import java.util.Date;
import java.util.LinkedHashMap;
import java.util.Map;

/**
 * Firebase Cloud Messaging over the HTTP v1 API. Needs a Firebase service-account key: point
 * {@code nest.push.fcm.credentials} at the JSON file (or put the JSON itself in the env var). With
 * nothing configured this reports {@link #isConfigured()} = false and every send is SKIPPED, so a
 * fresh checkout runs fine.
 *
 * <p>Uses jjwt (already on the classpath) to sign the OAuth assertion, rather than pulling in the
 * whole Firebase Admin SDK for one call.</p>
 */
@Component
public class FcmPushSender implements PushSender {

    private static final Logger log = LoggerFactory.getLogger(FcmPushSender.class);
    private static final String SCOPE = "https://www.googleapis.com/auth/firebase.messaging";

    private final ObjectMapper mapper;
    private final RestClient http = RestClient.create();
    private final String credentialsSource;

    private volatile Credentials credentials;
    private volatile boolean credentialsLoaded;
    private volatile String accessToken;
    private volatile Instant accessTokenExpiry = Instant.EPOCH;

    public FcmPushSender(ObjectMapper mapper, @Value("${nest.push.fcm.credentials:}") String credentialsSource) {
        this.mapper = mapper;
        this.credentialsSource = credentialsSource;
    }

    @Override
    public boolean isConfigured() {
        return credentials() != null;
    }

    @Override
    public ChannelResult send(String deviceToken, String title, String body, Map<String, String> data) {
        Credentials c = credentials();
        if (c == null) return ChannelResult.skipped("Push is not configured (nest.push.fcm.credentials)");
        try {
            Map<String, Object> message = new LinkedHashMap<>();
            message.put("token", deviceToken);
            message.put("notification", Map.of("title", title, "body", body));
            if (data != null && !data.isEmpty()) message.put("data", data);

            http.post()
                    .uri("https://fcm.googleapis.com/v1/projects/" + c.projectId + "/messages:send")
                    .header("Authorization", "Bearer " + accessToken(c))
                    .contentType(MediaType.APPLICATION_JSON)
                    .body(Map.of("message", message))
                    .retrieve()
                    .toBodilessEntity();
            return ChannelResult.sent();
        } catch (RestClientResponseException e) {
            String responseBody = e.getResponseBodyAsString();
            // 404 UNREGISTERED / 400 INVALID_ARGUMENT on the token = the app was uninstalled or
            // the token rotated. Tell the caller to drop it so we stop paying for dead sends.
            boolean dead = e.getStatusCode().value() == 404
                    || (responseBody != null && (responseBody.contains("UNREGISTERED")
                    || responseBody.contains("registration token is not a valid")));
            log.warn("FCM send failed: {} {}", e.getStatusCode(), responseBody);
            return dead ? ChannelResult.deadToken("FCM " + e.getStatusCode().value() + ": token no longer valid")
                    : ChannelResult.failed("FCM " + e.getStatusCode().value() + ": " + responseBody);
        } catch (Exception e) {
            log.warn("FCM send failed", e);
            return ChannelResult.failed(e.getClass().getSimpleName() + ": " + e.getMessage());
        }
    }

    private synchronized String accessToken(Credentials c) {
        if (accessToken != null && Instant.now().isBefore(accessTokenExpiry.minusSeconds(60))) return accessToken;

        Instant now = Instant.now();
        String assertion = Jwts.builder()
                .issuer(c.clientEmail)
                .claim("scope", SCOPE)
                .audience().add(c.tokenUri).and()
                .issuedAt(Date.from(now))
                .expiration(Date.from(now.plusSeconds(3600)))
                .signWith(c.privateKey, Jwts.SIG.RS256)
                .compact();

        MultiValueMap<String, String> form = new LinkedMultiValueMap<>();
        form.add("grant_type", "urn:ietf:params:oauth:grant-type:jwt-bearer");
        form.add("assertion", assertion);
        JsonNode response = http.post().uri(c.tokenUri)
                .contentType(MediaType.APPLICATION_FORM_URLENCODED)
                .body(form).retrieve().body(JsonNode.class);

        accessToken = response.get("access_token").asText();
        accessTokenExpiry = now.plusSeconds(response.path("expires_in").asLong(3600));
        return accessToken;
    }

    private Credentials credentials() {
        if (!credentialsLoaded) {
            synchronized (this) {
                if (!credentialsLoaded) {
                    credentials = load();
                    credentialsLoaded = true;
                }
            }
        }
        return credentials;
    }

    private Credentials load() {
        if (credentialsSource == null || credentialsSource.isBlank()) return null;
        try {
            String json = credentialsSource.trim().startsWith("{")
                    ? credentialsSource
                    : Files.readString(Path.of(credentialsSource.trim()), StandardCharsets.UTF_8);
            JsonNode node = mapper.readTree(json);
            String pem = node.get("private_key").asText()
                    .replace("-----BEGIN PRIVATE KEY-----", "")
                    .replace("-----END PRIVATE KEY-----", "")
                    .replaceAll("\\s", "");
            PrivateKey key = KeyFactory.getInstance("RSA")
                    .generatePrivate(new PKCS8EncodedKeySpec(Base64.getDecoder().decode(pem)));
            return new Credentials(node.get("project_id").asText(), node.get("client_email").asText(),
                    node.path("token_uri").asText("https://oauth2.googleapis.com/token"), key);
        } catch (Exception e) {
            log.error("FCM credentials could not be loaded - push stays disabled: {}", e.toString());
            return null;
        }
    }

    private record Credentials(String projectId, String clientEmail, String tokenUri, PrivateKey privateKey) {
    }
}
