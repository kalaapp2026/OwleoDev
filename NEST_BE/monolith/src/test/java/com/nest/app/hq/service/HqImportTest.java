package com.nest.app.hq.service;

import com.nest.app.hq.HqAudit;
import com.nest.app.identity.service.IdentityRegistrationService;
import com.nest.common.crypto.PiiHasher;
import com.nest.common.exception.BadRequestException;
import jakarta.persistence.EntityManager;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.mockito.junit.jupiter.MockitoSettings;
import org.mockito.quality.Strictness;
import org.springframework.jdbc.core.JdbcTemplate;

import java.time.LocalDate;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

/** What the bulk student file must satisfy before anyone is created. */
@ExtendWith(MockitoExtension.class)
@MockitoSettings(strictness = Strictness.LENIENT)
class HqImportTest {

    @Mock
    private JdbcTemplate jdbc;
    @Mock
    private HqAudit audit;
    @Mock
    private PiiHasher hasher;
    @Mock
    private IdentityRegistrationService registration;
    @Mock
    private EntityManager em;

    private HqImport importer() {
        return new HqImport(jdbc, audit, hasher, registration, em);
    }

    private static final Map<String, UUID> COURSES = Map.of("kathak", UUID.randomUUID(), "guitar", UUID.randomUUID());
    private static final Map<String, String> COURSE_NAMES = new LinkedHashMap<>(Map.of("kathak", "Kathak", "guitar", "Guitar"));
    private static final Map<String, List<String>> BATCH_NAMES = Map.of("kathak", List.of("Batch A", "Batch B"), "guitar", List.of());
    private static final Map<String, UUID> BATCHES = Map.of("kathak|batch a", UUID.randomUUID(), "kathak|batch b", UUID.randomUUID());

    /** A row that passes every rule. */
    private static Map<String, String> good() {
        Map<String, String> v = new LinkedHashMap<>();
        for (String c : HqImport.FULL_COLUMNS) v.put(c, "");
        v.put("name", "Ananya Rao");
        v.put("mobile", "9845012345");
        v.put("email", "ananya@example.in");
        v.put("gender", "female");
        v.put("date_of_birth", "14-05-2010");
        v.put("blood_group", "o+");
        v.put("guardian_name", "Suresh Rao");
        v.put("guardian_mobile", "9845012346");
        v.put("city", "Bengaluru");
        v.put("state", "Karnataka");
        v.put("pin_code", "560038");
        v.put("course", "kathak");
        v.put("batch", "batch a");
        v.put("joining_date", "01-06-2026");
        return v;
    }

    private List<HqImport.Issue> check(Map<String, String> v, boolean full) {
        List<HqImport.Issue> out = new ArrayList<>();
        importer().check(v, out, full, COURSES, COURSE_NAMES, BATCH_NAMES, BATCHES, new HashSet<>(), new HashSet<>());
        return out;
    }

    private static List<String> columns(List<HqImport.Issue> issues) {
        return issues.stream().map(HqImport.Issue::column).toList();
    }

    @Test
    void aCompleteRowPassesAndIsCleanedBeforeItIsCreated() {
        Map<String, String> v = good();
        v.put("mobile", "+91 98450-12345");

        assertThat(check(v, true)).isEmpty();
        assertThat(v.get("mobile")).isEqualTo("9845012345");
        assertThat(v.get("gender")).isEqualTo("Female");
        assertThat(v.get("blood_group")).isEqualTo("O+");
    }

    @Test
    void everyBadValueNamesItsColumnAndWhatToChange() {
        Map<String, String> v = good();
        v.put("name", "Ananya123");
        v.put("mobile", "98450");
        v.put("email", "not-an-email");
        v.put("gender", "M");
        v.put("date_of_birth", "31-02-2010");
        v.put("blood_group", "Z+");
        v.put("pin_code", "056001");
        v.put("joining_date", "tomorrow");

        List<HqImport.Issue> issues = check(v, true);

        assertThat(columns(issues)).containsExactlyInAnyOrder("name", "mobile", "email", "gender", "date_of_birth", "blood_group", "pin_code", "joining_date");
        assertThat(issues).allSatisfy(i -> assertThat(i.fix()).isNotBlank());
    }

    @Test
    void datesAreAcceptedInTheCommonShapesButMustBeRealDates() {
        assertThat(HqImport.date("14-05-2010")).isEqualTo(LocalDate.of(2010, 5, 14));
        assertThat(HqImport.date("14/05/2010")).isEqualTo(LocalDate.of(2010, 5, 14));
        assertThat(HqImport.date("2010-05-14")).isEqualTo(LocalDate.of(2010, 5, 14));
        assertThat(HqImport.date("4/5/2010")).isEqualTo(LocalDate.of(2010, 5, 4));
        assertThat(HqImport.date("31-02-2010")).isNull();
        assertThat(HqImport.date("2010-13-01")).isNull();
        assertThat(HqImport.date("soon")).isNull();
    }

    @Test
    void aDateOfBirthInTheFutureOrNearlyAHundredYearsBackIsRefused() {
        Map<String, String> future = good();
        future.put("date_of_birth", LocalDate.now().plusDays(3).format(java.time.format.DateTimeFormatter.ofPattern("dd-MM-yyyy")));
        Map<String, String> ancient = good();
        ancient.put("date_of_birth", "01-01-1900");

        assertThat(columns(check(future, true))).contains("date_of_birth");
        assertThat(columns(check(ancient, true))).contains("date_of_birth");
    }

    @Test
    void aStudentUnderEighteenNeedsAGuardianInTheFullTemplateOnly() {
        Map<String, String> v = good();
        v.put("guardian_name", "");
        v.put("guardian_mobile", "");

        assertThat(columns(check(new LinkedHashMap<>(v), true))).contains("guardian_name", "guardian_mobile");
        assertThat(check(new LinkedHashMap<>(v), false)).isEmpty();
    }

    @Test
    void anAdultNeedsNoGuardian() {
        Map<String, String> v = good();
        v.put("date_of_birth", "14-05-1990");
        v.put("guardian_name", "");
        v.put("guardian_mobile", "");

        assertThat(check(v, true)).isEmpty();
    }

    @Test
    void aCourseTheAcademyDoesNotHaveIsRefusedWithASuggestionAndTheList() {
        Map<String, String> v = good();
        v.put("course", "Kathk");
        v.put("batch", "");

        List<HqImport.Issue> issues = check(v, true);

        assertThat(issues).hasSize(1);
        assertThat(issues.get(0).column()).isEqualTo("course");
        assertThat(issues.get(0).fix()).contains("Did you mean Kathak").contains("Guitar");
    }

    @Test
    void courseNamesMatchWithoutRegardToCapitals() {
        Map<String, String> v = good();
        v.put("course", "KATHAK");
        v.put("batch", "BATCH b");

        assertThat(check(v, true)).isEmpty();
    }

    @Test
    void theFullTemplateNeedsTheCourseAndTheBatchWhereTheCourseHasBatches() {
        Map<String, String> noCourse = good();
        noCourse.put("course", "");
        noCourse.put("batch", "");
        Map<String, String> noBatch = good();
        noBatch.put("batch", "");
        Map<String, String> courseWithoutBatches = good();
        courseWithoutBatches.put("course", "Guitar");
        courseWithoutBatches.put("batch", "");

        assertThat(columns(check(noCourse, true))).containsExactly("course");
        assertThat(columns(check(noBatch, true))).containsExactly("batch");
        assertThat(check(courseWithoutBatches, true)).isEmpty();
        assertThat(check(new LinkedHashMap<>(noCourse), false)).isEmpty();
    }

    @Test
    void aBatchThatBelongsToAnotherCourseIsRefused() {
        Map<String, String> v = good();
        v.put("course", "Guitar");
        v.put("batch", "Batch A");

        List<HqImport.Issue> issues = check(v, true);

        assertThat(columns(issues)).containsExactly("batch");
        assertThat(issues.get(0).fix()).contains("no batches yet");
    }

    @Test
    void theSameMobileOrEmailTwiceInOneFileIsRefusedOnTheSecondRow() {
        HqImport importer = importer();
        var mobiles = new HashSet<String>();
        var emails = new HashSet<String>();
        List<HqImport.Issue> first = new ArrayList<>(), second = new ArrayList<>();

        importer.check(good(), first, true, COURSES, COURSE_NAMES, BATCH_NAMES, BATCHES, mobiles, emails);
        importer.check(good(), second, true, COURSES, COURSE_NAMES, BATCH_NAMES, BATCHES, mobiles, emails);

        assertThat(first).isEmpty();
        assertThat(columns(second)).containsExactlyInAnyOrder("mobile", "email");
    }

    @Test
    void aNumberOrEmailAlreadyOnOwleoIsRefused() {
        when(jdbc.queryForObject(anyString(), org.mockito.ArgumentMatchers.eq(Integer.class), any(Object[].class))).thenReturn(1);

        assertThat(columns(check(good(), true))).containsExactlyInAnyOrder("mobile", "email");
    }

    @Test
    void aPinCodeIsSixDigitsForIndiaAndLooserElsewhere() {
        Map<String, String> india = good();
        india.put("pin_code", "5600");
        Map<String, String> abroad = good();
        abroad.put("country", "United Kingdom");
        abroad.put("pin_code", "SW1A 1AA");

        assertThat(columns(check(india, true))).containsExactly("pin_code");
        assertThat(check(abroad, true)).isEmpty();
    }

    @Test
    void aUsernameIsTheFirstNameAndTheDayOfBirthThenTheSecondNameInitial() {
        List<String> c = HqImport.usernameCandidates("Vishruth Kumar", LocalDate.of(2002, 2, 22));

        assertThat(c.subList(0, 6)).containsExactly("vishruth22", "vishruthk22", "vishruth221", "vishruthk221", "vishruth222", "vishruthk222");
    }

    @Test
    void theNumberOnTheEndIsNeverMoreThanThreeDigitsAndTheNameNeverTooLong() {
        for (var dob : new LocalDate[]{LocalDate.of(2002, 2, 22), null}) {
            for (String name : List.of("Vishruth Kumar", "Meera", "Subramaniapuramvenkatesh Raghavendra")) {
                for (String u : HqImport.usernameCandidates(name, dob)) {
                    assertThat(u).matches("[a-z]+[0-9]{0,3}");
                    assertThat(u.replaceAll("^[a-z]+", "").length()).isLessThanOrEqualTo(3);
                    assertThat(u.length()).isBetween(3, 20);
                }
            }
        }
    }

    @Test
    void itRunsOutOfOptionsOnlyAfterAThousandOrSoNames() {
        assertThat(HqImport.usernameCandidates("Vishruth Kumar", LocalDate.of(2002, 2, 22))).hasSizeGreaterThan(900).doesNotHaveDuplicates();
        assertThat(HqImport.usernameCandidates("Meera Pillai", null)).hasSizeGreaterThan(900).doesNotHaveDuplicates();
    }

    @Test
    void aSingleNameHasNoInitialToTry() {
        assertThat(HqImport.usernameCandidates("Vishruth", LocalDate.of(2002, 2, 22)).subList(0, 3)).containsExactly("vishruth22", "vishruth221", "vishruth222");
    }

    @Test
    void theLastWordIsTheSecondNameWhenThereAreSeveral() {
        assertThat(HqImport.usernameCandidates("Anil Kumar Reddy", LocalDate.of(2000, 1, 9)).subList(0, 2)).containsExactly("anil09", "anilr09");
    }

    @Test
    void withoutADateOfBirthTheFirstNameIsTriedThenWithTheInitialThenNumbered() {
        List<String> c = HqImport.usernameCandidates("Meera Pillai", null);

        assertThat(c.subList(0, 4)).containsExactly("meera", "meerap", "meerap1", "meerap2");
    }

    @Test
    void aShortOrOddFirstNameStillMakesAValidUsername() {
        assertThat(HqImport.usernameCandidates("Jo", LocalDate.of(2010, 1, 5)).get(0)).isEqualTo("student05");
        assertThat(HqImport.usernameCandidates("A. R. Rahman", LocalDate.of(1990, 3, 3)).get(0)).matches("[a-z]{3,}03");
    }

    @Test
    void closestSuggestsOnlyNearNames() {
        assertThat(HqImport.closest("Kathk", List.of("Kathak", "Guitar"))).isEqualTo("Kathak");
        assertThat(HqImport.closest("Pottery", List.of("Kathak", "Guitar"))).isNull();
    }

    @Test
    void nothingIsCreatedWhenAnyRowIsBad() {
        UUID academy = UUID.randomUUID();
        when(jdbc.queryForList(anyString(), any(Object[].class))).thenAnswer(inv -> {
            String sql = inv.getArgument(0);
            return sql.contains("FROM academies") ? List.of(Map.<String, Object>of("name", "Nritya")) : List.of();
        });
        Map<String, Object> badRow = new LinkedHashMap<>();
        badRow.put("name", "Ananya Rao");
        badRow.put("mobile", "9845012345");
        badRow.put("course", "Kathak");   // the academy has no courses in this mock

        assertThatThrownBy(() -> importer().run(academy, List.of(badRow), true, "full")).isInstanceOf(BadRequestException.class).hasMessageContaining("nothing was created");
        verifyNoInteractions(registration);
    }

    @Test
    void aCheckReportsEveryProblemWithoutCreatingAnyone() {
        UUID academy = UUID.randomUUID();
        when(jdbc.queryForList(anyString(), any(Object[].class))).thenAnswer(inv -> {
            String sql = inv.getArgument(0);
            return sql.contains("FROM academies") ? List.of(Map.<String, Object>of("name", "Nritya")) : List.of();
        });
        Map<String, Object> row = new LinkedHashMap<>();
        row.put("Student Name", "Ananya Rao");   // headers may be written with spaces and capitals
        row.put("Phone", "12345");
        row.put("DOB", "bad");

        Map<String, Object> out = importer().run(academy, List.of(row), false, "full");

        assertThat(out.get("total")).isEqualTo(1);
        assertThat(out.get("ready")).isEqualTo(0);
        @SuppressWarnings("unchecked") List<Map<String, Object>> bad = (List<Map<String, Object>>) out.get("bad");
        assertThat(bad).hasSize(1);
        assertThat(bad.get(0).get("row")).isEqualTo(2);
        assertThat(bad.get(0).get("why").toString()).contains("mobile").contains("date_of_birth").contains("course");
        verifyNoInteractions(registration);
        verify(audit, org.mockito.Mockito.never()).log(anyString(), any(UUID.class), anyString());
    }
}
