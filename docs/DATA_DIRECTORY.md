# NEST — Data Directory

Where data lives, what each table is for, and what must never be shared. Schema is authoritative in
`NEST_BE/monolith/src/main/resources/db/migration/` (Flyway, `V1`…`V40`). Note: the repo has no
`V30`–`V32` files (numbering jumps V29 → V33); confirm against `flyway_schema_history` before
adding a migration, and always take the next number above the highest applied.

## Where data lives

| What | Location | Shareable? |
|---|---|---|
| Relational data | PostgreSQL, schema `nest` (local: `localhost:5432`, db `postgres`) | structure yes, rows no |
| Uploaded files (images, audio, documents) | `nest.upload.dir` = env `NEST_UPLOAD_DIR`, default `./uploads` (served by `FileStorageService`; 5 MB limit) | no |
| DB dumps | `D:\NEST\db_backups\*.sql` | **No — real user data** |
| Config / secrets | `application.properties` + env vars (`DB_*`, `nest.jwt.secret`, `nest.crypto.key`, `MAIL_*`, `NEST_CORS_ALLOWED_ORIGINS`, `NEST_PAYMENTS_MOCK_ENABLED`) | **Never share values**; share the variable *names* only |
| Device-side secrets | `flutter_secure_storage` (tokens), App Lock | n/a |
| Build output | `NEST_FE/build`, `dist/`, `owleo-nest-student.apk`, `NEST_BE/**/target` | no need |
| Crash noise | `hs_err_pid*.log`, `replay_pid*.log` at repo root (JVM crashes) | delete; do not commit |

## Tables by domain

**Identity & access**
`users` · `academy_memberships` (a person's role at one academy; has `salary`) · `feature_grants` ·
`course_feature_grants` (per-course grant) · `trainer_course_batches` · `refresh_tokens` ·
`otp_verifications` · `account_deletion_requests` · `device_installs`

**Academy**
`academies` · `academy_branches` · `academy_highlights` · `academy_highlight_images` ·
`academy_highlight_trainers` · `academy_featured_trainers` · `platform_settings` · `billing_plans` ·
`academy_invoices` · `artist_applications`

**Courses & batches**
`courses` · `course_map` · `batches` (start/end dates) · `batch_members` · `batch_trainers`

**Scheduling & attendance**
`schedules` · `class_instances` (substitute trainer, cancellation reason, reschedule overrides) ·
`attendance`

**Fees**
`fee_types` · `fee_type_batches` · `student_fees` · `fee_slips` · `fee_transactions` ·
`membership_pending_course_fees`

**Study material**
`study_materials` (keyed by **batch**) · `study_material_students` (per-student visibility) ·
`material_playlists` · `material_playlist_entries` · `material_playback_settings`
(tempo/volume/loop/trims per person per track)

**Events & messaging**
`events` (+ `event_batch_ids`, `event_course_ids`, `event_individual_ids`) · `academy_broadcasts`
(+ `_batch_ids`, `_course_ids`, `_individual_ids`) · `app_notifications`

**Social**
`posts` · `post_media_urls` · `interests` · `course_interests`

**Profile**
`user_achievements` · `user_performance_logs`

**Audit**: `audit_log`

**Legacy — deliberately kept, nothing reads them**
`syllabus_units`, `syllabus_unit_batches`, `syllabus_unit_materials`, `tracks`. Course Materials
merged into Study Material in V29. They stay because material on a course with no batches has
nowhere to land; one `yoga` syllabus file still lives only here. Do not drop without migrating it.

## Migration history (recent)

| | |
|---|---|
| V22 | course categories, icon keys, billing day, payment methods |
| V23 | batch start/end dates, `batch_trainers` |
| V24 | class instance overrides |
| V25 | `study_materials` |
| V26 | user profile detail columns, `trainer_course_batches` |
| V27 | `academy_memberships.salary` |
| V28 | material visibility, playlists, playback settings |
| V29 | Course Materials merged into Study Material |
| V33 | OTP email reset |
| V34 | academy profile contact and designation |
| V35 | event scheduling audience and status |
| V36 | academy broadcasts |
| V37 | achievements and performance logs |
| V38 | academy profile presets and address |
| V39 | student self-service |
| V40 | trim temporary batch classes (uncommitted at time of writing) |

## Sharing safely

Share: source, `docs/`, `.claude/skills/`, `CLAUDE.md`, migrations (schema only).
Do **not** share: `db_backups/`, `uploads/`, `.env`/property secrets, `hs_err_pid*.log`, APK.
To give someone realistic data, create a dump with a seeded dev academy rather than a real one
(`DevSuperAdminSeeder` seeds a dev super admin).
For a schema-only export:
`pg_dump -h localhost -U postgres -d postgres -n nest --schema-only > nest_schema.sql`
(`psql`/`pg_dump` live in `C:\Program Files\PostgreSQL\18\bin\`, not on PATH).
