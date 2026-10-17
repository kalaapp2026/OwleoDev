package com.nest.app.notification.channel;

import io.jsonwebtoken.Jwts;
import org.junit.jupiter.api.Test;

import java.nio.charset.StandardCharsets;
import java.security.KeyPair;
import java.security.KeyPairGenerator;
import java.util.Base64;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Google's token endpoint rejects an assertion whose {@code aud} is a JSON array ("Invalid JWT:
 * Failed audience check"). jjwt 0.12's {@code audience().add(x)} writes an array even for one
 * value; {@code audience().single(x)} writes the plain string. FcmPushSender must use the latter.
 */
class FcmAssertionAudienceTest {

    @Test
    void singleAudienceIsSerialisedAsAString() throws Exception {
        KeyPairGenerator gen = KeyPairGenerator.getInstance("RSA");
        gen.initialize(2048);
        KeyPair pair = gen.generateKeyPair();
        String uri = "https://oauth2.googleapis.com/token";

        String jwt = Jwts.builder().issuer("svc@example.iam").audience().single(uri)
                .signWith(pair.getPrivate(), Jwts.SIG.RS256).compact();

        String payload = new String(Base64.getUrlDecoder().decode(jwt.split("\\.")[1]), StandardCharsets.UTF_8);
        assertThat(payload).contains("\"aud\":\"" + uri + "\"").doesNotContain("\"aud\":[");

        String arrayJwt = Jwts.builder().audience().add(uri).and()
                .signWith(pair.getPrivate(), Jwts.SIG.RS256).compact();
        String arrayPayload = new String(Base64.getUrlDecoder().decode(arrayJwt.split("\\.")[1]), StandardCharsets.UTF_8);
        assertThat(arrayPayload).contains("\"aud\":[");
    }
}
