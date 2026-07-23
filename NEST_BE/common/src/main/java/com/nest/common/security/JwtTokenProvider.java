package com.nest.common.security;

import com.nest.common.exception.UnauthorizedException;
import io.jsonwebtoken.Claims;
import io.jsonwebtoken.ExpiredJwtException;
import io.jsonwebtoken.JwtException;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.security.Keys;
import org.springframework.stereotype.Component;

import javax.crypto.SecretKey;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.Date;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;

/**
 * Issues and parses the two token types used across NEST:
 * - access token: carries the full membership/feature/course claim list (PRD 4.3), short-lived.
 * - refresh token: minimal claims, long-lived, only ever exchanged at /auth/refresh.
 */
@Component
public class JwtTokenProvider {

    private static final String CLAIM_USERNAME = "username";
    private static final String CLAIM_GLOBAL_ROLE = "globalRole";
    private static final String CLAIM_MEMBERSHIPS = "memberships";
    private static final String CLAIM_ACTIVE_MEMBERSHIP = "activeMembershipId";
    private static final String CLAIM_TYPE = "type";

    private final JwtProperties properties;
    private final SecretKey signingKey;

    public JwtTokenProvider(JwtProperties properties) {
        this.properties = properties;
        this.signingKey = Keys.hmacShaKeyFor(properties.getSecret().getBytes(StandardCharsets.UTF_8));
    }

    public String generateAccessToken(NestPrincipal principal) {
        Instant now = Instant.now();
        List<Map<String, Object>> memberships = principal.memberships().stream()
                .map(this::toClaimMap)
                .collect(Collectors.toList());

        var builder = Jwts.builder()
                .subject(principal.userId().toString())
                .issuer(properties.getIssuer())
                .claim(CLAIM_USERNAME, principal.username())
                .claim(CLAIM_GLOBAL_ROLE, principal.globalRole().name())
                .claim(CLAIM_MEMBERSHIPS, memberships)
                .claim(CLAIM_TYPE, "access")
                .issuedAt(Date.from(now))
                .expiration(Date.from(now.plus(properties.getAccessTokenExpiryMinutes(), ChronoUnit.MINUTES)));

        if (principal.activeMembershipId() != null) {
            builder.claim(CLAIM_ACTIVE_MEMBERSHIP, principal.activeMembershipId().toString());
        }

        return builder.signWith(signingKey).compact();
    }

    public String generateRefreshToken(UUID userId) {
        return generateRefreshToken(userId, UUID.randomUUID());
    }

    /**
     * @param jti caller-supplied token id (JWT "jti" claim) - lets the caller persist a
     * server-side record keyed by this same id, so the token can be individually revoked on
     * logout instead of just expiring naturally. Without this, "log out" is unenforceable: a
     * stateless JWT stays valid until it expires no matter what the client does with it.
     */
    public String generateRefreshToken(UUID userId, UUID jti) {
        Instant now = Instant.now();
        return Jwts.builder()
                .id(jti.toString())
                .subject(userId.toString())
                .issuer(properties.getIssuer())
                .claim(CLAIM_TYPE, "refresh")
                .issuedAt(Date.from(now))
                .expiration(Date.from(now.plus(properties.getRefreshTokenExpiryDays(), ChronoUnit.DAYS)))
                .signWith(signingKey)
                .compact();
    }

    public Claims parse(String token) {
        try {
            return Jwts.parser().verifyWith(signingKey).build().parseSignedClaims(token).getPayload();
        } catch (ExpiredJwtException ex) {
            throw new UnauthorizedException("Token expired");
        } catch (JwtException | IllegalArgumentException ex) {
            throw new UnauthorizedException("Invalid token");
        }
    }

    public boolean isRefreshToken(Claims claims) {
        return "refresh".equals(claims.get(CLAIM_TYPE, String.class));
    }

    @SuppressWarnings("unchecked")
    public NestPrincipal toPrincipal(Claims claims) {
        UUID userId = UUID.fromString(claims.getSubject());
        String username = claims.get(CLAIM_USERNAME, String.class);
        Role globalRole = Role.valueOf(claims.get(CLAIM_GLOBAL_ROLE, String.class));
        List<Map<String, Object>> rawMemberships = claims.get(CLAIM_MEMBERSHIPS, List.class);
        List<MembershipClaim> memberships = rawMemberships == null ? List.of() : rawMemberships.stream()
                .map(this::fromClaimMap)
                .collect(Collectors.toList());
        String activeMembershipRaw = claims.get(CLAIM_ACTIVE_MEMBERSHIP, String.class);
        UUID activeMembershipId = activeMembershipRaw == null ? null : UUID.fromString(activeMembershipRaw);
        return new NestPrincipal(userId, username, globalRole, memberships, activeMembershipId);
    }

    private Map<String, Object> toClaimMap(MembershipClaim m) {
        return Map.of(
                "membershipId", m.membershipId().toString(),
                "academyId", m.academyId().toString(),
                "academyName", m.academyName() == null ? "" : m.academyName(),
                "roleType", m.roleType().name(),
                "features", m.features(),
                "courseIds", m.courseIds().stream().map(UUID::toString).collect(Collectors.toSet())
        );
    }

    @SuppressWarnings("unchecked")
    private MembershipClaim fromClaimMap(Map<String, Object> map) {
        Set<String> features = Set.copyOf((List<String>) map.getOrDefault("features", List.of()));
        Set<UUID> courseIds = ((List<String>) map.getOrDefault("courseIds", List.of())).stream()
                .map(UUID::fromString)
                .collect(Collectors.toSet());
        return new MembershipClaim(
                UUID.fromString((String) map.get("membershipId")),
                UUID.fromString((String) map.get("academyId")),
                (String) map.get("academyName"),
                Role.valueOf((String) map.get("roleType")),
                features,
                courseIds
        );
    }
}
