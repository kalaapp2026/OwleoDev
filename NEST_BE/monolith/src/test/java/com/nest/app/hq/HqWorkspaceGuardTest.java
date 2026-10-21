package com.nest.app.hq;

import com.nest.common.exception.ForbiddenException;
import com.nest.common.security.NestPrincipal;
import com.nest.common.security.Role;
import com.nest.common.security.TenantContext;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.mockito.junit.jupiter.MockitoSettings;
import org.mockito.quality.Strictness;
import org.springframework.jdbc.core.JdbcTemplate;

import java.util.List;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.when;

/** Finance data is refused until the Finance workspace has been opened with the emailed code. */
@ExtendWith(MockitoExtension.class)
@MockitoSettings(strictness = Strictness.LENIENT)
class HqWorkspaceGuardTest {

    @Mock
    private JdbcTemplate jdbc;

    @BeforeEach
    void signIn() {
        TenantContext.set(new NestPrincipal(UUID.randomUUID(), "owner", Role.SUPER_ADMIN, List.of(), null));
    }

    @AfterEach
    void signOut() {
        TenantContext.clear();
    }

    @Test
    void financeIsRefusedUntilTheWorkspaceIsOpen() {
        when(jdbc.queryForObject(anyString(), eq(Boolean.class), any(Object[].class))).thenReturn(false);

        assertThatThrownBy(() -> new HqAccess(jdbc).requireFinanceWorkspace()).isInstanceOf(ForbiddenException.class).hasMessageContaining("Finance workspace");
    }

    @Test
    void financeIsAllowedOnceTheWorkspaceIsOpen() {
        when(jdbc.queryForObject(anyString(), eq(Boolean.class), any(Object[].class))).thenReturn(true);

        assertThatCode(() -> new HqAccess(jdbc).requireFinanceWorkspace()).doesNotThrowAnyException();
    }

    @Test
    void theNewModulesBelongToTheRolesThatRunThem() {
        org.assertj.core.api.Assertions.assertThat(HqRole.FINANCE.canOpen("invoicing")).isTrue();
        org.assertj.core.api.Assertions.assertThat(HqRole.OPS.canOpen("invoicing")).isFalse();
        org.assertj.core.api.Assertions.assertThat(HqRole.OPS.canOpen("notifs")).isTrue();
        org.assertj.core.api.Assertions.assertThat(HqRole.FINANCE.canOpen("notifs")).isFalse();
        org.assertj.core.api.Assertions.assertThat(HqRole.SUPER.canOpen("invoicing")).isTrue();
    }
}
