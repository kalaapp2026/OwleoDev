# NEST / Owleo Nest — project context

Read this first. It is the handoff between sessions: what this is, how to run it, the conventions
that are already settled, and the traps that have cost real time. Everything here was verified
against the running system on **2026-09-06**, not recalled.

Point-in-time claims (module state, migration numbers, outstanding work) drift. Check `git log`
and the source before asserting any of it as still-true.

---

## What it is

A Flutter (web + Android + iOS) front end and a Spring Boot back end for performing-arts
academies — an ERP (courses, batches, scheduling, attendance, fees, materials, users) with a
Social side. Multi-tenant: every row is scoped to an academy, and a person can hold memberships at
several.

```
d:\NEST
├── NEST_FE\          Flutter app
├── NEST_BE\          Maven multi-module: `common` (shared) + `monolith` (the app)
├── NEST_ADMIN\       Flutter web app for the platform super admin (HQ Console), same backend
├── DEPLOY.md         web deployment, host comparison, CORS setup
└── CLAUDE.md         this file
```

Spring Boot 3.3.5 / Java 17 / Maven. PostgreSQL with Flyway, schema `nest`. Flutter with Riverpod,
go_router, Dio, fl_chart.

---

## Running it

**Backend** — from `d:\NEST\NEST_BE`:

```bash
mvn -pl monolith spring-boot:run
```

It serves on **port 8081**, not 8080. Endpoints sit at the root (`/courses`, `/students/...`), and
an unauthenticated request returns **401** — which is how you tell "routed and alive" from "not
deployed" (404).

**Frontend** — from `d:\NEST\NEST_FE`:

```bash
flutter run -d web-server --release --web-hostname 0.0.0.0 --web-port 5000
```

**Use `--release`.** The debug web-server only starts the app for the *first* browser that
connects; every later page load fetches all ~1030 DDC modules (all 200) and then stays a blank
white page forever, with no console error. Any test browser opened first "steals" it. Release serves
one `main.dart.js` (~5 MB) that renders in ~3 s on every load. Nothing is lost: a detached
`flutter run` can't hot-reload anyway. Verify with `curl .../main.dart.js` (~5 MB), not the DDC
`main_module.bootstrap.js` check below, which only applies to debug builds.

**Database** — `psql` is not on PATH:

```
C:\Program Files\PostgreSQL\18\bin\psql.exe   -h localhost -U postgres -d postgres
```

Password `root`, schema `nest`.

---

## Traps that have actually cost time

**A 200 on port 5000 proves nothing.** A dev server left running for days keeps answering while
serving a months-old bundle. This has caused a "nothing changed on localhost" report more than
once. Verify against the *compiled* output instead:

```bash
curl -s -o /dev/null -w "%{http_code}" \
  http://localhost:5000/packages/nest_fe/features/<path-without-lib>/<file>.dart.lib.js
curl -s http://localhost:5000/main_module.bootstrap.js | wc -c   # ~139 KB done, ~3 KB still building
```

Then grep the module for a string you just wrote. If two Dart files import each other, DDC merges
them into one bundle and the other's path 404s — that is a real signal to break the cycle, not a
build failure.

**A detached `flutter run` cannot receive `r`/`R`.** Every change needs a full restart.
`pkill -f "web-server"` does **not** match it on this machine — kill by PID:

```powershell
Get-NetTCPConnection -LocalPort 5000 -State Listen | Select-Object -ExpandProperty OwningProcess
```

If the port stays bound, the new server dies on bind and the old one keeps answering 200.

**`mvn test` fails while anything holds `monolith/target/`.** Byte Buddy reports
*"TestEngine with ID 'junit-jupiter' failed to discover tests"*. Culprits are a running
`spring-boot:run` **and** Spring processes spawned by the VS Code Java extension. Kill them by PID
(`Get-CimInstance Win32_Process`), then run the two phases separately:

```bash
mvn -q clean test-compile && mvn surefire:test
```

The VS Code Java extension also overwrites Maven's `target/test-classes` with its own output,
producing phantom "Unresolved compilation problems". Delete the stale `.class` and recompile.

**Shell.** Python is unavailable; Node is v18.18.0. Bash heredocs and `node -e` mangle backticks,
`$`, and `'''` — prefer the Write tool or a script file. Blanket `split().join()` replacements
across a Dart file have twice hit unintended matches; target exact lines. The same mangling eats
**backslashes** (`\b`, `\n`, `\d`) in `node -e` and `sed`, so a regex written there silently matches
nothing - an import-cleaning script that did this once stripped *every* import from 13 files. Write
scripts to a file with the Write tool, make each replacement fail loudly when its anchor is missing,
and only write the file when all of them matched.

Do not leave a shell's working directory inside `monolith/target/`: it locks the folder and
`mvn clean` fails with "Failed to delete …surefire-reports" - after which `surefire:test` quietly runs
the *stale* classes.

---

## Conventions that are settled

**Design tokens, not raw Material.** Screens are built from `ThemeExtension` tokens in
`lib/app/theme/`: `AppPalette`, `AppSpacing`, `AppRadii`, `AppMotion`, `AppShadows`, `AppType`.
Reach for `lib/core/design/` before writing a widget — `AttachedSelect` (with a `triggerBuilder`
escape hatch), `AppSegmentedControl`, `FlipToggle`, `Pressable`, `StatusBadge`, `showAppToast`,
`showAppConfirmDialog`, `showPeoplePickerSheet`, `showAppMultiSelectSheet`, `showAppCalendar`,
`showAppTimePicker`, `CourseIcon`, `PersonAvatar`.

There is no `AppMotion.house`. `AttachedSelect` is single-select; use
`showAppMultiSelectSheet` for multi.

**Per-course RBAC has three layers.** Getting this wrong is the single most repeated bug in this
project.

| | |
|---|---|
| `@RequiresFeature` | coarse gate on the controller — the union across courses |
| `CourseFeatureGuard.assertCourseFeature` | per-course **write** check |
| `CourseFeatureGuard.visibleCourseIds` | per-course **read/list** scoping |

`visibleCourseIds` returns `Optional<Set<UUID>>` where **empty Optional = no restriction** (admin)
and **empty Set = nothing visible**. Confusing the two shows a trainer the whole academy, or
shows them nothing.

A controller-level `@RequiresFeature` silently overrides any widening you do in the service — that
exact mistake shipped once and 403'd students out of a screen written for them.

**The recurring bug pattern.** Repeatedly, a query or provider scoped to "whole academy" or "whole
course" where it should have been scoped to one person's membership. If a report sounds like
*"someone can see data that isn't theirs"* or *"someone sees nothing"*, check scoping first.

**Course pickers open on their first course**, never on nothing — a picker over an empty body
reads as "there is no data". Course list queries are ordered by name
(`findByAcademyIdOrderByNameAsc`); without an explicit `ORDER BY`, Postgres reshuffles the
dropdown between loads.

### Data stays fresh without anyone remembering to refresh it (2026-10-24)

`AppShell` keeps every tab alive in an `IndexedStack`, so a tab's `autoDispose` providers never
dispose and never refetch on their own. The old answer was a hand-written `ref.invalidate` after each
save, which any save could forget. Now:

- **`DioClient`** (every one of the ~190 repository calls goes through `call`/`callVoid`) emits the path
  of each **successful write** on `DioClient.mutations` and empties the GET cache. `/auth/*`,
  `/devices/*`, push tokens, theme/language/notification prefs and the audio `…/playback` save are
  *background writes* and emit nothing.
- **`DataSync`** (`lib/app/data_sync/`) turns that into a refresh. `DataAreas.forSegment` maps the
  URL's first segment (`students`, `fees`, `me`…) to the **API providers** whose readers might now be
  stale; `DataSync.refresh` invalidates exactly the *live, async* providers that `ref.watch` one of
  those. A segment not in the map refreshes everything on screen (safe default). A new `FooApi`
  provider must be added to `DataAreas` or its readers will never be refreshed by a write.
- It also refreshes on **opening a tab** (data older than 20 s) and on **returning to the app** (older
  than 60 s) - that is how another person's change shows up. `DataFreshness` (a `ProviderObserver`
  installed by `AppRestart`) supplies "how old".
- A refresh keeps the old data on screen until the new lands (no spinner flash).
- **`GetCacheInterceptor`** coalesces identical in-flight GETs and reuses an answer for 5 s, cleared by
  any write. It sits *before* `AuthInterceptor` on purpose (a 401-retry resolves the request there and
  later interceptors never hear of it). Opt out per request with
  `extra: {GetCacheInterceptor.skip: true}`.

It relies on `ref.watch(xApiProvider)` inside the data provider (true of 90 of 93 today, none use
`ref.read`). Keep it that way.

### Validation (2026-10-24)

One rule set, used by every form and mirrored by the server.

- **App** - `lib/core/validation/`: `Validators` (name, email, username, password, PIN, amount, URL,
  handle, OTP, IFSC/UPI/PAN/GSTIN…), `InputFormats` (keystroke filters), `Country` (all 245 regions,
  206 calling codes, from the bundled libphonenumber metadata) and `PhoneRules` (per-country validity,
  UK-style trunk `0` stripped, mobile vs any). Widgets: `AppTextField`/`ValidatedTextField`/
  `CheckedField` with a `FieldPreset`, and `PhoneInput` (searchable country picker, paste of
  `+44 7400 123456` picks the country). A field judges its value **when you leave it, then live**
  (`FieldGuard`); `showErrors` forces it after a failed Save.
- **Server** - `com.nest.app.validation`: `FieldRules` + `@Phone`, `@PersonName`, `@Username`,
  `@StrictEmail`, `@StrongPassword`, `@PostalCode`, on the signup / registration / profile / password /
  onboarding DTOs. Phones are parsed with libphonenumber; a number with no `+code` is read as Indian.
  Null/blank always pass - requiredness is `@NotBlank`'s job. `PersonDetails` is `@Valid`-cascaded.
- Password policy everywhere: 8-72 characters, a letter and a number. Phones are stored `+91 9876543210`.
- `ApiException.message` now carries the first field error from a `VALIDATION_FAILED` reply, so screens
  that show `e.message` show the real reason.
- **Not covered:** `NEST_ADMIN` (HQ Console) forms and the HQ backend services still use their own
  10-digit `MOBILE` regex (`hq/service/Hq*.java`); a Super Admin entering a non-Indian number there is
  refused.

---

## Deployment

Backend is a Render web service, **`owleodev`**, built from `NEST_BE/Dockerfile`:
`https://owleodev.onrender.com`. It redeploys on push to `main`, and Flyway runs on start. Free
tier sleeps, so a cold first request can take a minute and return `000` mid-redeploy.

The API base URL is **compiled into** the bundle by `--dart-define`, so changing it needs a
rebuild, not a restart:

```bash
flutter build web --release --dart-define=API_BASE_URL=https://owleodev.onrender.com
flutter build apk --release --dart-define=API_BASE_URL=https://owleodev.onrender.com
```

To verify the URL really landed in an APK, look in `lib/*/libapp.so` — release builds are AOT, so
it is **not** in `kernel_blob.bin`.

`render.yaml` describes the static web site (`owleo-web`); `DEPLOY.md` covers Cloudflare and the
`NEST_CORS_ALLOWED_ORIGINS` variable the backend needs, without which the site loads and every
call fails.

---

## Module state — 2026-09-06

Six ERP modules were rebuilt against React prototypes (the `.jsx` files live in the user's
Downloads, not the repo): **Course Creation, Batch Creation, Schedule & Reschedule, Attendance,
Study Material, User Creation**. Fees was done earlier.

Recent migrations:

| | |
|---|---|
| V22 | course categories remapped, icon keys, billing day, payment methods |
| V23 | batch start/end dates, `batch_trainers` join |
| V24 | class instance overrides (substitute trainer, cancellation reason) |
| V25 | `study_materials` |
| V26 | user profile detail columns, `trainer_course_batches` |
| V27 | `academy_memberships.salary` |
| V28 | material visibility, playlists, playback settings |
| V29 | Course Materials merged into Study Material |

**Course Materials and Study Material are one feature.** They were the same idea in two models;
the batch-first one survived. Ordered syllabus chapters and their teaching status are gone. V29
migrated files and songs onto their unit's batches (`stream_only` → `VIEW_ONLY`).

The old tables — `syllabus_units`, `syllabus_unit_batches`, `syllabus_unit_materials`, `tracks` —
are **deliberately still there**. `study_materials` is keyed by batch, so material on a course
with no batches has nowhere to land; dropping them would destroy it silently. Nothing reads them.

Study Material is complete as of `ac8db0c`: per-student visibility, cross-batch Song/Document/
Image libraries, playlists (drag-reorder, repeat a song, per-entry actions), a file viewer, and a
practice player with tempo/volume arcs, loop and multi-segment trims saved per person per track.

Suites (re-run 2026-10-24): **462 backend tests** (monolith) + **9** in `common`; Flutter **298** in `NEST_FE`;
**23** in `NEST_ADMIN`.

**Cleanup done 2026-10-24:** the unbuilt microservice split (`gateway/`, 11 `services/*`, `infra/`), the
`InternalApiKeyFilter`, the old syllabus controller/service/entities (the tables stay), the legacy
`FeatureGrant`, the dead `FeesScreen`, ~16 unused Flutter API methods and ~20 unused repository methods
were deleted. Maven now builds two modules (`common`, `monolith`).

Endpoints with no caller in either Flutter app were deleted too, with their service methods, DTOs and tests
(the user asked for everything unused to go): the statement CSV download, `POST /courses/{id}/fee-slips/generate`,
`GET /fees/dashboard`, `/fees/report`, `/students/{id}/fees` and `/fee-slips`, `GET|POST /batches/{id}/class-instances`,
the single-item featured-trainer and highlight-image endpoints, `GET|PUT /admin/billing/academies/{id}/...`,
`/admin/hq/artists/counts`, `PUT /admin/hq/finance/expenses` (nothing in the HQ Console edits expenses, so
`hq_expenses` is now only read), `PUT /users/by-username/{u}/reset-password`, and the Testcontainers dependency
(unused; re-add it with the first integration test). To find more: run the scanners described in the session notes
or grep every controller path against the Dart code - a path built dynamically in NEST_ADMIN (e.g.
`/admin/hq/events/$id/${pause|cancel}`) will look unused to a plain search, so check before deleting.

**HQ onboarding has a Pre-lead stage (V64, V65):** Pre-lead -> Lead -> Demo -> Live (Dropped is the exit). A
pre-lead is only the academy's own details (name, type, city, state, one of phone/email, address optional): no
owner, plan or bank accounts. `POST /admin/hq/onboarding/preleads` adds one; `POST .../leads/{id}/promote` makes it a
lead (the lead form, academy fields pre-filled, asks for the owner/plan/banks); `POST .../leads/{id}/drop` drops a
pre-lead or lead. Rules live in `PreLeadRules`; the database `hq_leads_lead_complete` check keeps every Lead/Demo/Live
row complete. Start-demo and validate refuse a pre-lead.

---

## HQ Console (`NEST_ADMIN`)

A separate Flutter web app for the platform super admin, on this same backend and login (role
`SUPER_ADMIN`, narrowed by `users.hq_role`: SUPER/OPS/FINANCE/SUPPORT, NULL = SUPER). Backend code is
package `com.nest.app.hq` under `/admin/hq/**`; migrations **V48-V59, V61, V62** (V60 is the payment-orders table from the academy app). It covers dashboard, entities,
onboarding, collections, plans, growth, finance, approvals, transfers, users and students, master data,
courses, exits, reports, support, artist verification, events, marketing, service providers, platform
settings and the HQ team, and the Social tabs; plus, from prototype (3), Invoicing (the monthly bill run), Notification
templates, and a Finance workspace that is kept apart from business operations (opened with an emailed code, enforced
by the server). **Read `NEST_ADMIN/PLAN.md`**: it has how to run it
(including the demo-data backend on port 8082), the module map, the role table and an honest list of
what is a stand-in (events have no ticketing, marketing consent is never set, the dev OTP is fixed).

Two traps from that work apply everywhere: after calling a service that saves through JPA, call
`EntityManager.flush()` before a `JdbcTemplate` statement that needs the new row (otherwise an UPDATE
silently matches nothing or an insert hits a foreign key), and `Set.of(..).contains(null)` throws.
A deactivated user (`users.status = 'INACTIVE'`) is now refused at sign-in and refresh.

## Online fee payment (Razorpay, UPI only)

A student's **Pay now** opens Razorpay's checkout with UPI as the only method. Flow: `POST /me/fees/pay/order`
(server prices the fee from the ledger and opens a Razorpay order, stored in `payment_orders`, V60) →
checkout → `POST /me/fees/pay/verify` (checks Razorpay's HMAC signature) **and** the public webhook
`POST /payments/razorpay/webhook` (signature over the raw body). Both call one row-locked `settle()`, so a
fee is posted to `fee_transactions` exactly once. Nothing is marked paid on the client's word. Code:
`fees/gateway/RazorpayGateway`, `fees/service/OnlinePaymentService`; FE `fees/data/razorpay_checkout*.dart`
(web = `checkout.js` in `web/index.html`, mobile = `razorpay_flutter`).

It is OFF until `RAZORPAY_KEY_ID`, `RAZORPAY_KEY_SECRET` and `RAZORPAY_WEBHOOK_SECRET` are set on the backend
(use `rzp_test_` keys); `GET /me/fees/payment-config` reports `RAZORPAY` / `MOCK` / `NONE`. In Razorpay's
dashboard add a webhook to `https://<host>/payments/razorpay/webhook` for `payment.captured` and
`payment.failed`, with that same webhook secret.

**Not built yet:** money lands in NEST's own Razorpay account - per-academy settlement (Razorpay Route linked
accounts; `academy_bank_accounts.merchant_id` already exists for HQ to record one) still needs doing, and needs
Route enabled on the Razorpay account. The mobile (`razorpay_flutter`) path compiles into the app but has not
been run on a device. Paying the same fee in two tabs posts two payments (the ledger shows a credit).
`fee_transactions` is append-only (DB trigger): undo a test row with a reversing entry, never a DELETE.

## QA round (Oct 2026)

Fixes from the internal QA sheet; migration **V66** (`batches.meeting_link`). Worth knowing because they change behaviour:

- **Online classes.** A batch has an optional `meetingLink` (http/https, server-validated, trimmed; blank = none). It rides
  on `BatchResponse`, the schedule feed and the calendar, and the home schedule card and calendar show a **Join** button
  (`core/design/join_class_button.dart`). `updateBatch` is whole-set like the roster, so any caller that is not editing the
  link must pass the batch's current one back (the recurring-change screen does).
- **Trainer "Remove"** is `DELETE /courses/{courseId}/trainers/{membershipId}` (`TrainerRemovalService`): drops their
  `course_map` row, features, batch scoping and batch seats on that course. Students' Remove is still the reversible
  active flag. History (past classes, attendance) is left alone.
- **Notifications:** a row's check button marks it read (there is deliberately no delete); `NotificationRetentionJob`
  clears everything older than 60 days at 03:30 (`nest.notifications.retention-days`).
- **Photos:** student/trainer summaries and detail now carry `profileImageUrl`; the roster shows the photo and the edit
  form shows and uploads a new one.
- Back buttons are all `AppIconButton`; the theme no longer cross-fades (`themeAnimationDuration: Duration.zero`).
- A guardian's phone is required for a student; person names are letters and spaces only (any script).

Not done: the late-payment penalty (QA #27). `courses.due_day_of_month` is stored but nothing reads it, so there is no
overdue machinery to hang a penalty on; it needs a design call (base amount, ledger entry type, waiver) first.

## Outstanding

- **Documents have no in-app renderer.** The viewer shows a cover card and offers a download;
  Flutter ships no PDF or Office renderer, and adding one is a large dependency for something the
  device handles. A view-only document therefore cannot be read inside the app at all - worth
  revisiting if that turns out to matter.
- **i18n.** Every string in the rebuilt screens is hardcoded English — several hundred on top of
  the ~306 already outstanding.
- **No Spring/Testcontainers integration tests**, so the DB constraints in V21–V29 are verified
  only by hand against the dev database.
- Six Fees judgement calls the user said they would confirm later — most likely to be overruled:
  Other Fees totals are not month-scoped, and per-student one-off fees are excluded from the
  landing page's Other total.
- One syllabus file (on the batch-less `yoga` course) did not migrate in V29 and still lives only
  in the old tables.

---

## Working with this user

They test against the running app rather than reading code, and report bugs conversationally
("*in fees if i click the student detail error is occured*"). So: after any change, make sure both
servers are actually rebuilt and serving — verified against compiled output — before calling
anything done.

They prefer structured pickers (dropdowns, chips, grid dialogs) over free-text and raw ID fields,
and they want routine commands run without being asked for permission each time.
