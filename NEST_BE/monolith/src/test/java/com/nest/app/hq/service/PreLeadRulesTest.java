package com.nest.app.hq.service;

import org.junit.jupiter.api.Test;

import java.util.HashMap;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;

/** A pre-lead is the academy's own details only - no owner, no plan, no bank accounts. */
class PreLeadRulesTest {

    private static Map<String, Object> valid() {
        Map<String, Object> b = new HashMap<>();
        b.put("name", "Nrityanjali Dance Academy");
        b.put("type", "Dance");
        b.put("city", "Mysuru");
        b.put("state", "Karnataka");
        b.put("aphone", "9876543210");
        return b;
    }

    @Test
    void justTheAcademyDetailsAreEnough() {
        assertThat(PreLeadRules.problem(valid())).isNull();
    }

    @Test
    void anAccountIsNotAskedFor() {
        // nothing about an owner, a plan or banks appears in the rules at all
        Map<String, Object> b = valid();
        assertThat(b).doesNotContainKeys("owner", "ophone", "oemail", "plan", "est", "accts");
        assertThat(PreLeadRules.problem(b)).isNull();
    }

    @Test
    void anEmailAloneIsEnoughToReachThem() {
        Map<String, Object> b = valid();
        b.remove("aphone");
        b.put("aemail", "hello@nrityanjali.in");
        assertThat(PreLeadRules.problem(b)).isNull();
    }

    @Test
    void withNoPhoneOrEmailTheTeamCannotReachThem() {
        Map<String, Object> b = valid();
        b.remove("aphone");
        assertThat(PreLeadRules.problem(b)).contains("phone or email");
    }

    @Test
    void theBasicsAreRequired() {
        for (String key : new String[]{"name", "type", "city", "state"}) {
            Map<String, Object> b = valid();
            b.remove(key);
            assertThat(PreLeadRules.problem(b)).as("without " + key).isNotNull();
        }
        Map<String, Object> shortName = valid();
        shortName.put("name", "Ab");
        assertThat(PreLeadRules.problem(shortName)).contains("academy name");
    }

    @Test
    void theAddressIsOptionalButMustBeRightWhenGiven() {
        Map<String, Object> b = valid();
        b.put("a1", "");
        b.put("pin", "");
        assertThat(PreLeadRules.problem(b)).isNull();

        b.put("pin", "12345");
        assertThat(PreLeadRules.problem(b)).contains("6-digit PIN");
        b.put("pin", "570001");
        b.put("a1", "No");
        assertThat(PreLeadRules.problem(b)).contains("Address line 1");
        b.put("a1", "12 MG Road");
        assertThat(PreLeadRules.problem(b)).isNull();
    }

    @Test
    void aPhoneOrEmailThatIsGivenMustBeValid() {
        Map<String, Object> badPhone = valid();
        badPhone.put("aphone", "12345");
        assertThat(PreLeadRules.problem(badPhone)).contains("10-digit mobile");

        Map<String, Object> badEmail = valid();
        badEmail.put("aemail", "not-an-email");
        assertThat(PreLeadRules.problem(badEmail)).contains("valid academy email");
    }
}
