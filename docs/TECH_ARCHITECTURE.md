# NEST / Owleo Nest — Technical Architecture & Complete App Structure

Companion to [ARCHITECTURE.md](ARCHITECTURE.md) (short map) and
[NEST_Data_Dictionary_by_table.xlsx](NEST_Data_Dictionary_by_table.xlsx) (every table/column).

## 1. System context

```
 ┌──────────────────────────── Clients ────────────────────────────┐
 │  Flutter app  (one codebase)                                    │
 │  Web (static build)   Android (APK)   iOS                       │
 │  Riverpod state · go_router · Dio HTTP · secure token storage   │
 └───────────────────────────────┬─────────────────────────────────┘
                                 │ HTTPS + JSON, Bearer JWT
                                 │ (API_BASE_URL compiled in via --dart-define)
 ┌───────────────────────────────▼─────────────────────────────────┐
 │  Spring Boot 3.3.5 monolith (Java 17)  — Render service owleodev│
 │  port 8081 (local) · Swagger UI /swagger-ui.html · /actuator    │
 │  ┌─────────────── request pipeline ──────────────────────────┐  │
 │  │ CORS → JwtAuthFilter → ActivityTrackingFilter             │  │
 │  │ → Controller (@RequiresFeature via FeatureAuthorizationAspect)│
 │  │ → Service (CourseFeatureGuard, TenantContext)             │  │
 │  │ → Repository (Spring Data JPA) → PostgreSQL               │  │
 │  │ GlobalExceptionHandler → ErrorResponse                    │  │
 │  └───────────────────────────────────────────────────────────┘  │
 └───────┬───────────────────┬──────────────────┬──────────────────┘
         │ JDBC (Hikari, 5)  │ SMTP             │ local disk
 ┌───────▼───────┐   ┌───────▼──────┐   ┌───────▼───────────┐
 │ PostgreSQL     │   │ Mail server  │   │ uploads/ (files)  │
 │ schema `nest`  │   │ OTP/reset    │   │ FileStorageService│
 │ Flyway V1–V40  │   └──────────────┘   └───────────────────┘
 └────────────────┘
```

Shared library `common` (Maven module) supplies security, crypto, audit and exception handling to
the monolith. (An earlier microservice split - `gateway/`, `services/*`, `infra/` - was removed; it
never ran and is in git history.)

## 2. Technology stack

| Layer | Technology |
|---|---|
| Front end | Flutter (Dart SDK ^3.12), `flutter_riverpod` 2.6, `go_router` 14.6, `dio` 5.7, `flutter_secure_storage`, `fl_chart`, `audioplayers`, `file_picker`, `image_picker`, `share_plus`, `url_launcher`, `flutter_svg`, `intl` + ARB l10n |
| Back end | Java 17, Spring Boot 3.3.5, Spring Web, Spring Security (stateless JWT), Spring Data JPA/Hibernate (`ddl-auto=validate`), Flyway, springdoc OpenAPI, Spring Mail, AspectJ (feature + audit aspects), Maven multi-module |
| Database | PostgreSQL 18 (local) / Neon-hosted, schema `nest`, UUID keys, 58 tables |
| Hosting | Render (API, Docker from `NEST_BE/Dockerfile`); static web on Render `owleo-web` / Cloudflare Pages / Firebase |
| Tests | JUnit 5 + Mockito service tests (188), Flutter widget/unit tests (150) |

## 3. Cross-cutting design

**Multi-tenancy.** Every business row carries `academy_id` (directly or via its parent). The active
academy comes from the caller's membership claim (`TenantContext`); a user may hold several
memberships and switch between them.

**Authentication.** Login by username/password or OTP (`AuthController`, `OtpService`).
Access JWT 15 min + refresh token 30 days (`refresh_tokens`, revocable). JWT carries user, role and
per-academy membership claims with feature keys (`MembershipClaim`, `JwtTokenProvider`).
`PrincipalAssembler` builds the `NestPrincipal`. Temporary passwords force a change on first login.

**Authorisation — three layers** (full rules in skill `nest-rbac-scoping`):
`@RequiresFeature` (controller gate, `FeatureAuthorizationAspect`) →
`CourseFeatureGuard.assertCourseFeature` (per-course write) →
`CourseFeatureGuard.visibleCourseIds` (per-course read scope). Roles: SUPER_ADMIN, ACADEMY_ADMIN,
TRAINER, STUDENT, ARTIST, GUEST. 13 feature keys; `COURSE_MANAGEMENT` and `ABOUT_US_EDIT` are not
delegable.

**PII protection.** Phone, DOB, address, alt phone and emergency contact are stored encrypted
(`EncryptedStringConverter`, key `nest.crypto.key`); lookups use `PiiHasher` hashes
(`phone_hash`, `email_hash`).

**Auditing.** `@Auditable` + `AuditAspect` → `JpaAuditPublisher` → `audit_log`.

**Errors.** `NestException` subclasses (BadRequest, Conflict, Forbidden, NotFound, Unauthorized,
TooManyRequests) → `GlobalExceptionHandler` → `ErrorResponse`; the app maps these to
`ApiException` and toasts.

**Activity metrics.** `ActivityTrackingFilter` updates `users.last_seen_at`; the app pings
`device_installs` for install counts (Super Admin console).

**Files.** Uploads go through `FileStorageService` to `nest.upload.dir` (5 MB cap) and are
referenced by URL columns (`study_materials.url`, `*_image_url`, …).

**Notifications.** Rows in `app_notifications` (ERP/SOCIAL module) created by services (membership
confirmation, broadcasts); the bell polls the API. OTP/reset emails via SMTP.

**Billing.** Platform plans (`billing_plans`) and monthly `academy_invoices` per academy; a mock
payment mode exists behind `NEST_PAYMENTS_MOCK_ENABLED`.

**Front-end state flow.** `SessionController` (auth state, active membership, `UserProfile`) →
`dio_client` + `AuthInterceptor` (attach token, refresh on 401) → per-feature `*_api.dart` →
Riverpod providers → screens. `kErpActions` drives both the Dashboard tile grid and the More sheet.

## 4. Module map (what talks to what)

```
identity ──► every module (principal, memberships, feature grants)
academy ◄── curriculum (courses) ◄── enrolment (batches, members, trainers)
enrolment ──► scheduling (class_instances) ──► attendance
enrolment/course_map ──► fees (slips, transactions, other fees)
curriculum.study_materials ──► batch_members (visibility)
event, message ──► notification ──► app_notifications
profile / selfservice ──► attendance, fees, curriculum (student-scoped reads)
platform, billing ──► academy (super-admin side)
social ──► event, academy (posts, interests)
dashboard, calendar ──► read-only aggregation over the above
```

## 5. Back-end structure (`NEST_BE`)

```
NEST_BE/
├── pom.xml                         parent POM (modules)
├── Dockerfile                      Render image
├── common/src/main/java/com/nest/common/
│   ├── audit/       AuditAspect, AuditEvent, AuditPublisher, Auditable, Slf4jAuditPublisher
│   ├── config/      CommonAutoConfiguration
│   ├── crypto/      CryptoProperties, EncryptedStringConverter, PiiEncryptor, PiiHasher
│   ├── dto/         ErrorResponse, PageResponse
│   ├── exception/   NestException + BadRequest/Conflict/Forbidden/NotFound/TooManyRequests/
│   │                Unauthorized/UpstreamService, GlobalExceptionHandler
│   └── security/    JwtAuthFilter, JwtProperties, JwtTokenProvider, MembershipClaim, NestPrincipal,
│                    NestAuthenticationEntryPoint, TenantContext, Role, FeatureKey, RequiresFeature,
│                    FeatureAuthorizationAspect, InternalApiKeyFilter/Properties
├── monolith/
│   ├── src/main/resources/
│   │   ├── application.properties
│   │   └── db/migration/V1 … V40   Flyway (no V30–V32 files)
│   ├── src/test/java/com/nest/app/<domain>/{service,controller,repository}
│   └── src/main/java/com/nest/app/
│       ├── NestApplication
│       ├── config/       SecurityConfig, WebConfig (CORS), OpenApiConfig
│       ├── bootstrap/    DevSuperAdminSeeder, LegacyPasswordBackfill
│       ├── storage/      FileStorageService
│       ├── audit/        AuditLog, AuditLogRepository, JpaAuditPublisher
│       └── <domain>/     controller · dto · entity · repository · service   (below)
```

### Domain packages (`com.nest.app.*`)

| Package | Controllers | Services | Entities |
|---|---|---|---|
| `identity` | AuthController, UserController, ArtistApplicationController | AuthService, OtpService, UserService, IdentityRegistrationService, MembershipConfirmationService, PrincipalAssembler, **CourseFeatureGuard**, ArtistApplicationService, SmtpEmailSender/EmailSender, OtpSender/LoggingOtpSender, TempPasswordGenerator | User, AcademyMembership, FeatureGrant, CourseFeatureGrant, CourseMap, TrainerCourseBatch, RefreshToken, OtpVerification, ArtistApplication |
| `academy` | AcademyController, AcademyProfileController | AcademyService, AcademyProfileService | Academy, AcademyBranch, AcademyHighlight(+Image), AcademyFeaturedTrainer |
| `curriculum` | CourseController, StudyMaterialController, MaterialPlaylistController, SyllabusController | CourseService, StudyMaterialService, MaterialPlaylistService, MaterialPlaybackService, SyllabusService (legacy) | Course, StudyMaterial, StudyMaterialStudent, MaterialPlaylist(+Entry), MaterialPlaybackSettings, MaterialAttachment, SyllabusUnit, Track (legacy) |
| `enrolment` | BatchController, StudentController, TrainerController | BatchService, StudentRegistrationService, TrainerRegistrationService | Batch, BatchMember, BatchTrainer |
| `scheduling` | SchedulingController | SchedulingService, ScheduleFeedService, RescheduleService | Schedule, ClassInstance |
| `attendance` | AttendanceController | AttendanceService | Attendance |
| `fees` | FeesController, OtherFeesController, FeesDashboardController | FeesService, FeeSlipService, OtherFeesService, StudentPaymentService, FeesDashboardService | FeeSlip, FeeTransaction, FeeType(+Batch), StudentFee |
| `billing` | BillingController | BillingService | BillingPlan, AcademyInvoice |
| `event` | EventController | EventService | Event |
| `message` | BroadcastController | BroadcastService | AcademyBroadcast |
| `notification` | NotificationController | NotificationService | AppNotification |
| `social` | PostController | PostService, InterestService | Post, Interest |
| `profile` | SelfProfileController | SelfProfileService | UserAchievement, UserPerformanceLog |
| `selfservice` | StudentSelfController | StudentSelfService | AccountDeletionRequest, CourseInterest |
| `platform` | PlatformMetricsController, PlatformSettingsController, DeviceController | PlatformMetricsService, AcademyStatsService, PlatformSettingsService, DeviceInstallService, ActivityTracker (+ `ActivityTrackingFilter`) | PlatformSettings, DeviceInstall |
| `dashboard` | DashboardController | DashboardService | — (aggregates) |
| `calendar` | CalendarController | CalendarService | — (aggregates) |

~200 REST endpoints in total across 31 controllers.

## 6. Front-end structure (`NEST_FE`)

```
NEST_FE/
├── pubspec.yaml · analysis_options.yaml · l10n.yaml · firebase.json · flutter_launcher_icons.yaml
├── android/ ios/ web/ (index.html, manifest.json, _headers, icons)     platform shells
├── assets/brand/ (owl_icon.png) · assets/icon/
├── tool/ add_l10n_keys.mjs                                             l10n helper
├── test/ 14 test files (api_paths, attendance, batch_and_time, design_components, fee_format,
│         material_playlist, schedule_entry, student_fee_profile, study_material, tokens, …)
└── lib/
    ├── main.dart
    ├── l10n/                       generated ARB localisations
    ├── app/
    │   ├── app.dart                MaterialApp.router, theme + locale wiring
    │   ├── router/app_router.dart  all routes + auth redirect (_RootGate, _WithNavBar)
    │   ├── theme/                  app_colors, app_tokens, app_typography, app_theme, theme_controller
    │   └── i18n/                   app_languages, locale_controller
    ├── core/
    │   ├── auth/       feature_keys, membership_summary, session_controller, session_state, user_profile
    │   ├── network/    api_config, dio_client, auth_interceptor
    │   ├── storage/    secure_token_storage
    │   ├── security/   app_lock
    │   ├── providers/  core_providers
    │   ├── error/      api_exception
    │   ├── format/     money
    │   ├── design/     app_date_picker, app_top_bar, attached_select, avatar, buttons, calendar_modal,
    │   │               category_meta, charts, confirm_dialog, course_icons, day_of_month_field,
    │   │               flip_toggle, gold_tabs, people_picker_sheet, pressable, segmented_control,
    │   │               sheets, status_badge, time_picker_sheet, toast
    │   └── widgets/    app_notice, async_value_view, avatar, owleo_wordmark
    └── features/       (each: data/ = API + models, presentation/ = screens + widgets)
```

### Feature modules → screens

| Feature | Data layer | Screens (presentation) |
|---|---|---|
| `auth` | auth_api | login, signup, become_artist |
| `shell` | erp_action (domain) | app_shell (header, bottom nav), more_menu_sheet |
| `dashboard` | dashboard_api, dashboard_stats | dashboard_screen; widgets: admin/student welcome headers, cover_header, stats_row, revenue_dues_card, todays_schedule_card, upcoming_events_card, student_summary, student_material_strip |
| `academy` | academy_profile(_api), academy_billing_api, academy_onboarding_api | academy_info, academy_profile_edit, academy_management, academy_settings, academy_billing, academy_onboarding, change_password, trainer_card, academy_profile_shared |
| `curriculum` | course, curriculum_api, study_material(_api), material_playlist, syllabus_api/unit (legacy) | course_list, course_form, my_courses, study_material_home, batch_material, material_library, upload_material, playlists, file_viewer; widgets: audio_player_panel, markup_overlay, material_row |
| `enrolment` | batch, enrolment_api, person_details, user_tab | batch_list, batch_form, user_list, user_form, student_search, student_dashboard, student_roster_picker, trainer_picker; widgets: feature_catalog, form_fields, user_dialogs |
| `scheduling` | scheduling_api, calendar_api, schedule_entry, calendar_class | schedule_screen, calendar_screen, class_detail, recurring_change; widgets: inline_month_calendar, reason_chips, schedule_action_sheets, schedule_row |
| `attendance` | attendance_api, class_instance, student_attendance | attendance_home, mark_attendance, student_attendance_home, student_attendance |
| `fees` | fees_api, fee_summary, fee_roster, fee_type, fee_transaction, transaction_ledger, student_fee_profile, student_statement, student_other_fees | fees_landing, fees, regular_fees, other_fees, student_fees, student_profile, student_pay_sheet, statement, all_transactions, add_fee_type, add_student_fee; widgets: revenue_card, student_list_body, student_other_fees_tab |
| `events` | events_api, event | event_list, event_detail, event_form, student_events |
| `messages` | messages_api, broadcast | messages_home, broadcast_compose |
| `notification` | notification_api | notifications, broadcast |
| `profile` | self_profile(_api) | my_profile, edit_my_profile, profile, user_settings, record_screens (achievements/logs); widgets/sections |
| `social` | social_api, people_search_api, post, post_permission | feed, create_post, my_posts, events_tab, search_profiles, user_profile_posts, post_grid |
| `artist_application` | artist_application_api | artist_applications |
| `platform` (Super Admin) | platform_api, billing_api, platform_settings_api, device_install_service | super_admin_dashboard, academy_detail, academy_stats, billing, platform_settings, console_layout |

### Route table (`app_router.dart`)

Public: `/login`, `/signup`, `/become-artist`. Root: `/home` (role gate). Profile: `/profile`.
ERP (inside the nav bar): `/erp/courses`, `/erp/my-courses`, `/erp/batches`, `/erp/scheduling`,
`/erp/calendar`, `/erp/attendance`, `/erp/events`, `/erp/events/new`, `/erp/messages`,
`/erp/study-materials`, `/erp/students`, `/erp/students/new` (Users), `/erp/academy`,
`/erp/academy-settings`, `/erp/academies/new` (Super Admin), `/erp/my-profile`, `/erp/my-settings`.

## 7. Environments and configuration

| Setting | Dev | Prod |
|---|---|---|
| API URL | `localhost:8081` | `https://owleodev.onrender.com` via `--dart-define=API_BASE_URL` |
| DB | `DB_HOST/PORT/NAME/USER/PASSWORD/SCHEMA/SSLMODE` env | same, Neon |
| Secrets | `nest.jwt.secret`, `nest.crypto.key`, `nest.crypto.hmac-key` | Render env (never committed) |
| CORS | local origins | `NEST_CORS_ALLOWED_ORIGINS` |
| Mail | `MAIL_HOST` (default localhost:1025) | `MAIL_*` env |
| Files | `./uploads` | `NEST_UPLOAD_DIR` (Render disk is ephemeral unless a volume is mounted — verify) |

## 8. Build, test, release

- Back end: `mvn -pl monolith spring-boot:run`; tests `mvn -q clean test-compile && mvn surefire:test`.
- Front end: `flutter run -d web-server --release --web-port 5000`; `flutter analyze && flutter test`;
  release builds with `flutter build web|apk --release --dart-define=API_BASE_URL=…`.
- CI/CD: push to `main` → Render builds the Dockerfile and Flyway migrates on start.
- Known gaps: no Testcontainers integration tests, hardcoded English strings (i18n), no in-app
  document renderer, legacy syllabus tables still present.
