package com.nest.app.hq;

import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * The role table is the console's security boundary, so what each role may open, change and export
 * is pinned here rather than left to the data the server happens to return.
 */
class HqRoleTest {

    @Test
    void aMissingOrUnknownRoleIsSuperAdminBecauseTheSeededOwnerHasNone() {
        assertThat(HqRole.of(null)).isEqualTo(HqRole.SUPER);
        assertThat(HqRole.of("NOT_A_ROLE")).isEqualTo(HqRole.SUPER);
        assertThat(HqRole.of("FINANCE")).isEqualTo(HqRole.FINANCE);
    }

    @Test
    void superAdminOpensEverything() {
        assertThat(HqRole.SUPER.canOpen("master")).isTrue();
        assertThat(HqRole.SUPER.canOpen("anything-at-all")).isTrue();
    }

    @Test
    void onlySuperAndOperationsCanMakeChanges() {
        assertThat(HqRole.SUPER.canWrite()).isTrue();
        assertThat(HqRole.OPS.canWrite()).isTrue();
        assertThat(HqRole.FINANCE.canWrite()).isFalse();
        assertThat(HqRole.SUPPORT.canWrite()).isFalse();
    }

    @Test
    void supportCannotExportButFinanceCan() {
        assertThat(HqRole.SUPPORT.canExport()).isFalse();
        assertThat(HqRole.FINANCE.canExport()).isTrue();
    }

    @Test
    void masterDataAndSettingsAreSuperAdminOnly() {
        for (HqRole r : new HqRole[]{HqRole.OPS, HqRole.FINANCE, HqRole.SUPPORT}) {
            assertThat(r.canOpen("master")).as(r + " opens master data").isFalse();
            assertThat(r.canOpen("settings")).as(r + " opens settings").isFalse();
            assertThat(r.canOpen("transfers")).as(r + " opens transfers").isFalse();
        }
    }

    @Test
    void financeSeesMoneyAndSupportSeesPeopleButNotTheOtherWayRound() {
        assertThat(HqRole.FINANCE.canOpen("collections")).isTrue();
        assertThat(HqRole.FINANCE.canOpen("users")).isFalse();
        assertThat(HqRole.SUPPORT.canOpen("users")).isTrue();
        assertThat(HqRole.SUPPORT.canOpen("finance")).isFalse();
    }
}
