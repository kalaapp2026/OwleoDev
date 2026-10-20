package com.nest.app.hq;

import com.nest.app.hq.service.HqMaster;
import com.nest.app.hq.service.HqTeam;
import com.nest.common.exception.BadRequestException;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.mockito.junit.jupiter.MockitoSettings;
import org.mockito.quality.Strictness;
import org.springframework.jdbc.core.JdbcTemplate;

import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.verifyNoInteractions;

/** Input the console must refuse before it touches the database. */
@ExtendWith(MockitoExtension.class)
@MockitoSettings(strictness = Strictness.LENIENT)
class HqValidationTest {

    @Mock
    private JdbcTemplate jdbc;
    @Mock
    private HqAudit audit;

    @Test
    void aMasterDataItemNeedsARealName() {
        HqMaster master = new HqMaster(jdbc, audit);

        assertThatThrownBy(() -> master.add("batches", " a ")).isInstanceOf(BadRequestException.class);
        assertThatThrownBy(() -> master.add("batches", null)).isInstanceOf(BadRequestException.class);
        verifyNoInteractions(jdbc);
    }

    @Test
    void anUnknownMasterDataListIsRejected() {
        HqMaster master = new HqMaster(jdbc, audit);

        assertThatThrownBy(() -> master.add("passwords", "Something")).isInstanceOf(BadRequestException.class);
    }

    @Test
    void aTeamLoginNeedsAValidNamePhoneEmailAndRoleBeforeAnythingIsCreated() {
        HqTeam team = new HqTeam(jdbc, audit, null, null);

        assertThatThrownBy(() -> team.invite("Al", "valid.user", "9876543210", "a@b.in", "OPS")).as("short name").isInstanceOf(BadRequestException.class);
        assertThatThrownBy(() -> team.invite("Alice Rao", "A B", "9876543210", "a@b.in", "OPS")).as("bad username").isInstanceOf(BadRequestException.class);
        assertThatThrownBy(() -> team.invite("Alice Rao", "alice.rao", "12345", "a@b.in", "OPS")).as("bad phone").isInstanceOf(BadRequestException.class);
        assertThatThrownBy(() -> team.invite("Alice Rao", "alice.rao", "9876543210", "not-an-email", "OPS")).as("bad email").isInstanceOf(BadRequestException.class);
        assertThatThrownBy(() -> team.invite("Alice Rao", "alice.rao", "9876543210", "a@b.in", "GOD")).as("bad role").isInstanceOf(BadRequestException.class);
        verifyNoInteractions(jdbc);
    }
}
