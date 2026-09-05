# NEST / Owleo Nest — project context

Read this first. It is the handoff between sessions: what this is, how to run it, the conventions
that are already settled, and the traps that have cost real time. Everything here was verified
against the running system on **2026-09-05**, not recalled.

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
flutter run -d web-server --web-hostname 0.0.0.0 --web-port 5000
```

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
across a Dart file have twice hit unintended matches; target exact lines.

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

## Module state — 2026-09-05

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

Suites: **180 backend tests**, **134 Flutter tests**. Both green at `e4c1fb6`.

---

## Outstanding

- **The new Study Material prototype is unbuilt on the front end.** V28's tables
  (`material_playlists`, `material_playlist_entries`, `material_playback_settings`) are live and
  mapped but **nothing writes to them**. Still to build: cross-batch Song/Document/Image
  libraries, playlists with drag-reorder and repeat-a-song, a fullscreen document/image viewer,
  and the custom audio player (vinyl disk, radial speed/volume levers, multi-segment trims with
  per-segment tempo, loop, saved settings).
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
