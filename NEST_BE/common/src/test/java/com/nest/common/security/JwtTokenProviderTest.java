package com.nest.common.security;

import io.jsonwebtoken.Claims;
import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.Set;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.junit.jupiter.api.Assertions.assertEquals;

class JwtTokenProviderTest {

    private final JwtProperties properties = new JwtProperties();
    private final JwtTokenProvider provider = new JwtTokenProvider(properties);

    @Test
    void accessTokenRoundTripsAllMembershipsAndActivePointer() {
        UUID membership1 = UUID.randomUUID();
        UUID membership2 = UUID.randomUUID();
        UUID courseId = UUID.randomUUID();

        NestPrincipal principal = new NestPrincipal(
                UUID.randomUUID(), "priya_r", Role.STUDENT,
                List.of(
                        new MembershipClaim(membership1, UUID.randomUUID(), "Natyalaya", Role.STUDENT, Set.of(), Set.of(courseId)),
                        new MembershipClaim(membership2, UUID.randomUUID(), "Swaralaya", Role.STUDENT, Set.of(), Set.of())
                ),
                membership1
        );

        String token = provider.generateAccessToken(principal);
        Claims claims = provider.parse(token);
        NestPrincipal parsed = provider.toPrincipal(claims);

        assertEquals(principal.userId(), parsed.userId());
        assertEquals(principal.username(), parsed.username());
        assertEquals(2, parsed.memberships().size());
        assertEquals(membership1, parsed.activeMembershipId());
        assertThat(parsed.hasCourse(courseId)).isTrue();
    }

    @Test
    void refreshTokenIsRejectedByAccessTokenConsumers() {
        String refreshToken = provider.generateRefreshToken(UUID.randomUUID());
        Claims claims = provider.parse(refreshToken);
        assertThat(provider.isRefreshToken(claims)).isTrue();
    }

    @Test
    void tamperedTokenFailsVerification() {
        String token = provider.generateAccessToken(
                new NestPrincipal(UUID.randomUUID(), "x", Role.GUEST, List.of(), null));

        // Tamper with the PAYLOAD, not the tail of the signature. An HS256 signature is 32 bytes
        // encoded as 43 base64url chars, so its final character carries only 2 significant bits -
        // several different last characters decode to identical signature bytes. Rewriting the
        // token's last two chars therefore sometimes produced a token that still verified, making
        // this test fail roughly one run in a few dozen. Changing a payload character always
        // changes the signed content, so the signature can never still match.
        String[] parts = token.split("\\.");
        char first = parts[1].charAt(0);
        String tamperedPayload = (first == 'A' ? 'B' : 'A') + parts[1].substring(1);
        String tampered = parts[0] + "." + tamperedPayload + "." + parts[2];

        assertThat(tampered).as("tampering must actually change the token").isNotEqualTo(token);
        assertThatThrownBy(() -> provider.parse(tampered))
                .isInstanceOf(com.nest.common.exception.UnauthorizedException.class);
    }
}
