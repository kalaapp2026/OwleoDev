# NEST / Owleo Nest — Architecture

A Flutter (web, Android, iOS) front end and a Spring Boot back end for performing-arts academies:
an ERP (courses, batches, scheduling, attendance, fees, study material, users) plus a Social side.
**Multi-tenant**: every row is scoped to an academy, and one person can hold memberships at several.

Day-to-day commands, traps and conventions live in [`../CLAUDE.md`](../CLAUDE.md). This file is the
map; read both.

## Repository layout

```
NEST/
├── CLAUDE.md            session handoff: how to run, traps, settled conventions
├── DEPLOY.md            web deployment, host comparison, CORS
├── render.yaml          static web site (owleo-web) on Render
├── wrangler.jsonc       Cloudflare deploy config
├── docs/                this documentation set
├── .claude/skills/      Claude Code skills for this project
├── db_backups/          SQL dumps of real data  (PRIVATE - never share)
├── NEST_BE/             Maven multi-module back end
│   ├── common/          shared: Role, FeatureKey, security, JWT, @RequiresFeature
│   ├── monolith/        THE APP - the only module that runs
│   └── Dockerfile       Render build
└── NEST_FE/             Flutter app
```

## Back end — `NEST_BE/monolith`

Spring Boot 3.3.5, Java 17, Maven. PostgreSQL, schema `nest`, Flyway migrations, JPA with
`ddl-auto=validate` (a migration must match the entities or boot fails). Port **8081**; endpoints
are at the root (`/courses`, `/students/...`). Unauthenticated → **401** (404 means not deployed).
Swagger UI at `/swagger-ui.html`.

Package root `com.nest.app`, one package per domain, each split `controller / dto / entity /
repository / service`:

| Package | Responsibility |
|---|---|
| `identity` | users, memberships, auth (login, refresh, OTP reset), trainers, students, feature grants |
| `academy` | academy, branches, profile (about, highlights, featured trainers, presets) |
| `curriculum` | courses, course map, study materials, playlists, playback settings, syllabus (legacy) |
| `enrolment` | batches, batch members, batch trainers |
| `scheduling` | schedules, class instances, reschedule/cancel/substitute, schedule feed |
| `attendance` | attendance marking and reports |
| `fees` | fee types, student fees, slips, transactions, other fees, fees dashboard |
| `billing` | academy plans and invoices (platform side) |
| `event`, `message`, `notification` | events, broadcasts, in-app notifications, devices |
| `social` | posts, interests, course interests |
| `profile`, `selfservice` | a user's own profile/achievements/logs; student self-service endpoints |
| `platform` | super-admin metrics, platform settings, activity tracking, artist applications |
| `dashboard`, `calendar` | read-only aggregation for home screens |
| `audit`, `storage`, `config`, `bootstrap` | audit log, file storage, security/CORS config, dev seeder |

### Roles and access

Roles (`common/.../Role.java`): `SUPER_ADMIN → ACADEMY_ADMIN → TRAINER → STUDENT` (ERP branch),
`ARTIST`, `GUEST` (Social-only). A Super Admin has no academy membership of their own.

Trainers get capabilities through **feature grants** (`FeatureKey`): `COURSE_MANAGEMENT`,
`STUDENT_REGISTRATION`, `TRAINER_REGISTRATION`, `BATCH_CREATION`, `BATCH_SCHEDULING`, `RESCHEDULE`,
`ATTENDANCE`, `FEES_ENTRY`, `FEES_DASHBOARD`, `SYLLABUS_EDIT`, `EVENT_MANAGEMENT`, `ABOUT_US_EDIT`,
`ARTIST_STYLE_POSTING`. `COURSE_MANAGEMENT` and `ABOUT_US_EDIT` are never delegable. Grants may be
per course (`course_feature_grants`). Admins are not gated by grant rows.

**Three enforcement layers — keep all three consistent** (see skill `nest-rbac-scoping`):

1. `@RequiresFeature` on the controller — coarse gate, union across courses.
2. `CourseFeatureGuard.assertCourseFeature` — per-course **write** check.
3. `CourseFeatureGuard.visibleCourseIds` — per-course **read/list** scoping
   (`Optional.empty()` = unrestricted admin; empty `Set` = nothing visible).

### Auth

JWT access token (15 min) + refresh token (30 days, stored in `refresh_tokens`). Memberships and
feature grants travel as claims. Passwords/OTP via `otp_verifications`; email via SMTP.

## Front end — `NEST_FE`

Flutter, Riverpod (state), go_router (navigation), Dio (HTTP), fl_chart, flutter_secure_storage,
audioplayers (practice player), file_picker, image_picker, intl (+ `l10n.yaml`).

```
lib/
├── main.dart
├── app/        app.dart, router/ (all routes), theme/ (design tokens), i18n/
├── core/       auth/ (UserProfile, FeatureKeys), network/ (dio, api_config, auth_interceptor),
│               design/ (shared widgets), security/ (App Lock), storage/, format/, error/, providers/, widgets/
├── features/   one folder per domain, each with data/ (API + models) and presentation/ (screens)
│               academy, artist_application, attendance, auth, curriculum, dashboard, enrolment,
│               events, fees, messages, notification, platform, profile, scheduling, shell, social
└── l10n/
```

The **More** menu and Dashboard tiles both render from one list, `kErpActions`
(`features/shell/domain/erp_action.dart`), filtered per user by role and feature. Bottom tabs:
Dashboard, Attendance, Fees (+ More). To add a screen: route in `app/router`, tile in `kErpActions`,
screen in `features/<domain>/presentation`, API in `features/<domain>/data`.

UI is built from `ThemeExtension` tokens (`AppPalette`, `AppSpacing`, `AppRadii`, `AppMotion`,
`AppShadows`, `AppType`) and the shared widgets in `core/design/` — see skill `nest-flutter-ui`.

## Deployment topology

| Piece | Where |
|---|---|
| API | Render web service `owleodev` (`https://owleodev.onrender.com`), Docker, redeploys on push to `main`, Flyway on start, free tier sleeps |
| Web | Static Flutter build (Render `owleo-web` / Cloudflare / Firebase) |
| DB | PostgreSQL (local dev; Neon in the hosted setup per the backup file names) |
| Mobile | `flutter build apk` with `--dart-define=API_BASE_URL=...` |

The API URL is compiled into the bundle (`--dart-define`), so changing it needs a rebuild.
CORS: the backend needs `NEST_CORS_ALLOWED_ORIGINS` set to the web origin or every call fails.
