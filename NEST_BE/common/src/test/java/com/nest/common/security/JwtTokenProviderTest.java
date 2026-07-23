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
        String tampered = token.substring(0, token.length() - 2) + "xx";

        assertThatThrownBy(() -> provider.parse(tampered))
                .isInstanceOf(com.nest.common.exception.UnauthorizedException.class);
    }
}
