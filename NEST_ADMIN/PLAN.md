# Owleo HQ Console (NEST_ADMIN): handoff

The platform super admin's web app. A separate Flutter project (package `owleo_hq`) on the **same
Spring Boot backend and the same login** as the academy app, built from the prototype
`Owleo HQ Console (3).html` (earlier builds followed (2); (3) is the current reference). It is web-first; it is Flutter so it can become an app later.

Why separate from `NEST_FE`: the academy bundle is already ~5 MB, super admin has ~25 modules, and it
is a different audience and security surface. Nothing here imports `NEST_FE` (that would drag
firebase/pdf plugins into the web build). Code the two share (Dio client, tokens) was copied; pulling
it into a package is a later refactor.

Check `git log` and the source before trusting anything below as still true.

---

## Run it

```bash
# backend (port 8081, schema `nest`) - from d:\NEST\NEST_BE
mvn -pl monolith spring-boot:run

# console (dev) - from d:\NEST\NEST_ADMIN
flutter run -d web-server --release --web-hostname 0.0.0.0 --web-port 5100
```

Sign in as `superadmin` / `SuperAdmin@123` (the dev super admin seeded by the backend). Use
`--release`, same reason as the academy app (debug web-server only serves the first browser).

The API base URL is compiled in: `--dart-define=API_BASE_URL=http://localhost:8081` (default) or the
deployed URL. Changing it needs a rebuild.

### Demo data (a throwaway second backend)

The real dev database holds one academy, so most screens look empty. A **demo backend** fills a
separate schema with ~45 academies, 2,100 people, bills, tickets, artists, events, providers and so on:

```bash
# creates the schema if missing, seeds it on first start, refuses to run against `nest`
SERVER_PORT=8082 DB_SCHEMA=nest_hqdemo NEST_HQ_DEMO_ENABLED=true mvn -pl monolith spring-boot:run

flutter build web --release --dart-define=API_BASE_URL=http://localhost:8082 --output build/web_demo
```

Same login; demo people have password `Demo@1234`. To reseed: stop it, `DROP SCHEMA nest_hqdemo CASCADE;
CREATE SCHEMA nest_hqdemo;`, start again. The seeder is `com.nest.app.hq.demo.HqDemoSeeder`. It is a
fixed-seed generator, so the demo is the same every time. It runs as an `ApplicationRunner`, which can
fire **before** the app's own super-admin bootstrap, so it must not assume that user exists.

### Tests

`mvn -q clean test-compile && mvn surefire:test` (kill any running Spring first, see the root
CLAUDE.md): backend tests (HQ ones in `monolith/src/test/.../hq`). `flutter test` in this folder: formatting, JSON
reading, role rules, CSV parsing, demo-period text and the workspace split.

---

## How it is built

```
lib/
  app/            theme (tokens ported from the prototype CSS), router (go_router, hash URLs)
  core/api        Dio client with refresh-token interceptor; session + roles in core/auth
  core/ui         the widget kit: cards, KPIs, tables, charts, selects, drawers, modals, toasts
  features/<m>/   one folder per module (screen + its drawers/modals/providers)
  features/shell  header, floating dock, "More" sheet, logo flip HQ<->Social, module gate
```

State is Riverpod `FutureProvider.autoDispose` per read; a write calls the API and invalidates the
providers it affects. Screens are built from `lib/core/ui` and the tokens in `lib/app/theme.dart`;
reach for those before writing a widget. Pickers are structured (dropdown, chips, date picker), never
raw ID fields.

Backend: package `com.nest.app.hq`, everything under `/admin/hq/**`, every controller
`@PreAuthorize("hasRole('SUPER_ADMIN')")` plus `HqAccess` (below). Read models are `JdbcTemplate` SQL
(needs `spring.datasource.hikari.schema=${DB_SCHEMA:nest}`); anything that must go through existing
services (creating accounts, onboarding an academy) calls them.

### Roles

`users.hq_role`: `SUPER`, `OPS`, `FINANCE`, `SUPPORT`. **NULL means SUPER** (the seeded owner has none).
Read on every request, so a role change takes effect immediately. The server enforces; the app only
locks tiles and hides buttons.

| Role | Opens | Changes things |
|---|---|---|
| Super | everything (incl. Master data, Settings, Transfers, Providers) | yes |
| Operations | users, academies, onboarding, approvals, courses, exits, reports, artists, events, support, alerts, notifs | yes |
| Finance | finance, plans, growth, collections, invoicing, marketing, reports, approvals, academies, support | plans, collections, invoicing, marketing only |
| Support | users, students, courses, exits, artists, events, support, alerts | replies on tickets |

Writing = Super or Operations, except plans/collections/invoicing/marketing (Super or Finance). Export = Super,
Operations, Finance.

---

## Modules

| Module | App | Backend | Tables (migration) |
|---|---|---|---|
| Dashboard (Business + Platform status) | `dashboard/` | `HqOverviewController`, `HqPlatform` | reads (V48) |
| Entities / academies | `academies/` | `HqAcademyController`, `HqAcademyService`, `HqImport` | V49, V51 |
| Onboarding (Pre-lead, Lead, Demo, Live) | `onboarding/` | `HqOnboardingController`, `HqOnboarding`, `PreLeadRules` | `hq_leads` (V54, V64, V65) |
| Collections | `collections/` | `HqCollectionsController`, `HqBilling`, `HqCatalog` | V50, V52 |
| Plans | `plans/` | `HqPlansController` | V49 |
| Growth, Finance (revenue only) | `growth/`, `finance/` | `HqInsightsController` | V50 |
| Invoicing (monthly bill run) | `invoicing/` | `HqInvoicingController`, `HqInvoicing`, `HqBilling` | V62 |
| Notification templates | `notifications/` | `HqNotificationsController`, `HqNotifications`, `HqNotificationCatalogue`, `HqChannels` | V62 |
| Payments (transactions + account mapping) | `payments/` | `HqPaymentsController`, `HqPayments` | V68 `invoice_payment_orders`, `invoice_payments.source` |
| Finance workspace gate | `shell/workspace.dart` | `HqTeamController` `/workspace`, `HqWorkspace`, `HqAccess.requireFinanceWorkspace` | V61 |
| Approvals | `approvals/` | `HqApprovalsController`, `HqApprovals` | V53 |
| Academy transfer | `transfers/` | `HqTransfers` (real OTPs via `OtpService`) | V58 |
| Users (Audience + Students) | `users/` | `HqUsersController`, `HqUsers`, `HqStudentsController`, `HqStudents` | V55, V59 (`marketing_consent`) |
| Master data | `master/` | `HqMasterController`, `HqMaster` | V55 |
| Courses | `courses/` | `HqCoursesController`, `HqCourses` | existing batch tables |
| Exits | `exits/` | `HqExitsController`, `HqExits` (uses the EXIT workflow) | V55 |
| Reports + audit trail | `reports/` | `HqReportsController`, `HqReports`, `HqAudit` | V48 |
| Support tickets | `support/` | `HqSupportController`, `HqSupport` | V56 |
| Artist verification | `artists/` | `HqArtistsController`, `HqArtists` | V57 (extends `artist_applications`) |
| Events | `events/` | `HqEventsController`, `HqEvents` | V57 `hq_event_log` |
| Marketing | `marketing/` | `HqMarketingController`, `HqMarketing` | V59 |
| Service providers | `providers/` | `HqProvidersController`, `HqProviders` | V59 |
| Platform settings + HQ team | `settings/` | `HqTeamController`, `HqPlatform`, `HqTeam` | `users.hq_role` |
| Social (Post, Event, Search, Profile) | `social/` | `HqSocialController`, `HqSocial` | existing `posts` |
| Alerts | `alerts/` | `HqOverviewController`, `HqAlerts` | derived |

Behaviour worth knowing:

- **Two workspaces, never open together (prototype 3).** Business operations and Finance (Revenue,
  Collections, Invoicing) are separate. Opening Finance needs a 6-digit code emailed to the signed-in
  person (`OtpPurpose.FINANCE_WORKSPACE`, fixed `123456` in dev) and lasts 8 hours (`hq_workspace_grants`).
  The **server** refuses finance data without it (`requireFinanceWorkspace` on the collections, finance and
  invoicing controllers) and the Dashboard no longer returns money at all; the app only hides the other
  workspace's tiles. The Finance page is revenue only: no costs, profit or P&L (expenses still exist in the
  database from V50 but nothing reads them).
- **Revenue groups**: Platform fees = plan + setup + credits/other adjustments; Marketing fees =
  `MARKETING` lines; Other service fees = add-ons + `COMMISSION` lines. Marketing and commission lines are
  added by hand from Collections ("Counts as revenue from") because the apps do not bill them yet.
- **Pre-lead comes before Lead.** An academy HQ has only heard of is added as a pre-lead with just its own details
  (no owner, plan or banks; `AcademyFormData.issues(preLead: true)`). "Make lead" opens the lead form with those
  filled in; "Drop" retires either stage. A dropped row keeps whatever it had, so V65 lets DROPPED rows be
  incomplete while the table still forces LEAD, DEMO and LIVE rows to be.
- **Academies pay their bill online.** Academy admin > Billing & Subscription (`NEST_FE`, `GET /academies/me/billing`) shows every
  plan with the academy's own highlighted, every add-on on sale with the ones it has marked ACTIVE, and each bill with GST, lines and
  receipts. **Pay** opens Razorpay (UPI, card, net banking) for the whole balance: `POST .../pay/order` prices it on the server,
  the browser's signed result goes to `POST .../pay/verify`, and the same webhook as student fees (`/payments/razorpay/webhook`)
  settles it if the browser closes. Settling is row-locked and idempotent (`SubscriptionPaymentService`); the money lands in
  **Owleo's own** Razorpay account. It is a normal `invoice_payments` row with `source = ONLINE`, so Collections, Finance and the
  academy's receipt all see it. With no gateway keys the Pay button says to pay Owleo directly and have HQ record it.
- **Payments (HQ, Finance workspace)**: Transactions = every subscription payment (online or by hand), checkouts that were started
  but not paid or failed, and student-fee payments through Owleo's gateway, filterable and exportable. Account mapping = Owleo's
  receiving account status plus, per academy, its bank account and the gateway merchant id it is mapped to (the same mapping the
  academy drawer edits). Student fees are collected into Owleo's account, so that mapping is what settlement to the academy needs.
- **Demo length is in days** (`hq_leads.demo_days`, 15 to 90; the form offers 15 days, 1 month, 45 days,
  2 months, 3 months or custom).
- **Invoicing** makes real `academy_invoices` rows (so they appear in Collections). One schedule row
  (`hq_invoice_settings`), one draft per academy for the next run (`hq_invoice_drafts`: edited lines, offer or
  % or ₹ discount for 1 to 12 bills, note, skip, keep), and a run row per month (`hq_invoice_runs`). The daily
  job (`HqCollectionsJobs.monthlyBills`) generates on the generate day and sends on the send day when
  "Run automatically" is on. Bills are sent to the academy admins in the Owleo Nest app (a real bell
  notification) and by email; a bill counts as sent only if someone was reached. Email counts as set up only
  when `MAIL_HOST` is not localhost; WhatsApp only with its credentials (`HqChannels`).
- **Notification templates** are a design store (`hq_notification_templates`), seeded once with 18
  starting templates. Only the in-app test send and the Monthly bill message are used by anything real; the
  four events the platform fires today still read the older `notification_templates` (V42). The delivery
  log is the real `notification_deliveries` table.

- **Deactivating a person is real.** `AuthService.issueTokens` refuses `users.status = 'INACTIVE'`, so a
  deactivated account cannot sign in or refresh; deactivation also revokes sessions and sets academy
  memberships to `REVOKED` (reactivating restores them).
- **Approving an artist with posting on makes them `ARTIST`** (the role the feed checks);
  suspension/switch-off returns them to `GUEST`. A third upheld report bans for good and the account
  can never re-apply.
- **Contact details are masked everywhere.** Only `POST /admin/hq/users/{id}/reveal` returns one, and
  it writes an audit line each time; the edit form's source is logged the same way.
- **Billing is one engine.** The academy app's `BillingService` delegates to `HqBilling`, so both
  consoles write the same lines, GST and numbers (`INV-YYMM-NNN`, numbered from the highest suffix, not
  a count). Legacy invoices keep `gst_rate = 0`.
- **Academy status is derived**, never stored: closed -> churned; suspended; has a demo end date ->
  trial; overdue bill -> past due; else live. Health = attendance 30% + fee collection 35% + weekly
  active 35% (missing parts reweighted).

---

## What is not built, or is a stand-in (be honest with the owner about these)

- **Events have no ticketing**, so the prototype's registrations, capacity, price and 5% commission do
  not exist. The screen shows "interested" (the only audience signal recorded). Billing the commission
  needs ticket data first.
- **Artists "can host events" is stored but not enforced**: only academies can create events today.
  Reports on artists are logged by HQ staff; there is no in-app "report this artist" yet.
- **Social**: no likes, comments or reports are recorded, so none are shown. Official posts are PUBLIC
  only (no audience targeting). Removing a post is permanent.
- **Providers**: academies cannot request a service from their app; HQ logs requests. "Send a warning"
  is recorded in the history, not delivered. No media is stored by design.
- **Marketing**: Owleo does not place ads. Spend, reach, clicks and leads are typed in from the ad
  platform. Audience counts use `users.marketing_consent`, which defaults to **false** and which
  nothing in the apps sets yet, so on real data every audience is 0 until consent is collected.
- **Notification templates do not drive sending yet** (except the Monthly bill message). Wiring a moment
  such as "Fee overdue" means calling the dispatcher where it happens; the page says so. Email sends have no
  row in the delivery log (it has no email channel). Push and WhatsApp tests are logged as skipped.
- **Online bill payment** needs `RAZORPAY_KEY_ID` / `RAZORPAY_KEY_SECRET` (and `RAZORPAY_WEBHOOK_SECRET`) on the backend. Nothing
  has been paid through real Razorpay yet; the order call, signature check and webhook are tested with test keys and
  hand-made signed requests, not against Razorpay's servers. Only the full balance can be paid online. Asking for an add-on is a
  support request to HQ; HQ still assigns it in Collections. **Per-academy settlement** of student fees (moving money from
  Owleo's account to each academy's) is NOT built: the mapping is recorded, nothing is transferred (needs Razorpay Route).
- **Invoicing**: event commission is not on these bills (no ticketing). WhatsApp bills are not sent (the
  option is saved and reported as not set up). The Finance code is emailed through the existing OTP sender.
- **Transfers**: codes go through the existing `OtpService`, which uses the fixed code **123456** in
  development. Replace that and wire a real SMS sender before any real transfer.
- **Platform status** shows what the database and JVM can report (latency, memory, uptime, sessions,
  notification failures, who signed in). It is not infrastructure monitoring or error telemetry.
- **Users**: the profile edit covers personal details; the academy mapping (course, batch, trainer) is
  shown but not editable, and branch is not shown (no per-person branch exists).
- **Not built from the prototype**: "Open as admin" (impersonation); a time-limited "give access" for a
  bank-account change; logo upload on Add academy; WhatsApp/SMS delivery of payment reminders.
- **Scale**: the Users list reads all non-HQ people into memory per request to compute the "missing
  data" counts (fine for thousands, page it in SQL before 100k+).
- **No Testcontainers integration tests** (same as the academy backend): the DB constraints in V48-V62
  were verified by hand against the dev schema and the demo schema.
- **i18n**: every string is hardcoded English.

## Traps found while building (they cost real time)

- **JPA saves are not flushed before JDBC.** After calling an existing service that persists through
  JPA (`createUserWithPassword`, `onboardAcademy`, `createMembership`), call `EntityManager.flush()`
  before a `JdbcTemplate` update/insert that depends on the new row. Without it the UPDATE silently
  matches 0 rows or the insert hits a foreign key. This produced an invited staff member with no role
  (treated as Super!) and a failing "start demo".
- **`Set.of(...).contains(null)` throws NPE** (a 500, not a 400). Null-check input before `contains`.
- **Count-based numbering collides** after any deletion; number from `max + 1`.
- **A detached `flutter run` cannot hot reload**; rebuild and restart, and verify against the compiled
  bundle, as in the root CLAUDE.md.
- **Header titles** are resolved from the first path segment; strip the query string first
  (`/users?tab=students`).

## Deploying

A second static site, same pattern as `owleo-web` (see `render.yaml` / `DEPLOY.md`): build with
`flutter build web --release --dart-define=API_BASE_URL=<backend>` from `NEST_ADMIN`, and add the
site's origin to `NEST_CORS_ALLOWED_ORIGINS` on the backend or every call fails. Flyway migrations
V48-V62 and V68 run on backend start (V60 to V67 are the academy app's). (V60 is the academy app's `payment_orders`; HQ jumped to V61/V62 because
it landed first on the user's database.)
