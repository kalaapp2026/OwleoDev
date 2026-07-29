# Deploying the Owleo Nest web app

The backend (`owleodev`) is already a Render web service built from `NEST_BE/Dockerfile`.
This covers putting the **Flutter web app** online and pointing it at that backend.

---

## Step 1 - Allow the web app's origin on the backend (do this FIRST)

Without this, the deployed site loads fine and then **every API call fails** - login included.
The browser blocks the request before it reaches any backend code, so the logs look clean and
nothing obviously "errors". Verified against the live backend: a preflight from a non-localhost
origin currently returns `403` with no `Access-Control-Allow-Origin` header.

In the Render dashboard on the **owleodev** service → Environment, add:

| Key | Value |
| --- | --- |
| `NEST_CORS_ALLOWED_ORIGINS` | `https://owleo-web.kalaapp2026.workers.dev` |

Comma-separate if you add a custom domain later:
`https://owleo-web.kalaapp2026.workers.dev,https://app.owleonest.com`

Save - Render redeploys automatically. Confirm it took effect:

```bash
curl -s -D - -o /dev/null -X OPTIONS https://owleodev.onrender.com/auth/login \
  -H "Origin: https://owleo-web.kalaapp2026.workers.dev" \
  -H "Access-Control-Request-Method: POST" | grep -i access-control-allow-origin
```

You want a header back. Nothing means it isn't applied yet.

---

## Choosing a free host

A Flutter web build is heavy: a first-time visitor downloads roughly **4MB** (1.1MB of gzipped
JS plus the multi-MB wasm renderer). Repeat visits are nearly free because assets are cached, but
that first-load figure is what decides whether a free tier is actually usable.

| Host | Free bandwidth | ~Fresh visits/month | Verdict |
| --- | --- | --- | --- |
| **Cloudflare Pages** | unlimited | unlimited | **Recommended** - see Option B |
| **Render** (static) | 100 GB/mo | ~25,000 | Also configured here (`render.yaml`) |
| Netlify / Vercel | 100 GB/mo | ~25,000 | Fine |
| **Firebase Hosting** | 360 MB/**day** | ~90/day | Fine for demos; tight for real use |

Firebase's limit is per *day*, not per month - about **90 first-time visitors daily** at 4MB each.
That's genuinely fine while you're testing and sharing a link with a few people, and genuinely
limiting once an academy's students start using it. It's the one number worth knowing before
picking it.

All three steps below (CORS, SPA rewrite, `--dart-define`) are needed on **every** host. Only the
upload command differs.

---

## Option A - Firebase Hosting

One-time setup:

```bash
npm install -g firebase-tools
firebase login
cd NEST_FE
firebase init hosting     # existing project or create one
```

`firebase init` will ask about the public directory and SPA rewrite. **`firebase.json` is already
committed** with the right answers (public `build/web`, rewrite everything to `/index.html`, long
cache on assets, no-cache on `index.html`) - so if the wizard offers to overwrite it, say **no**.

Every deploy:

```bash
cd NEST_FE
flutter build web --release --dart-define=API_BASE_URL=https://owleodev.onrender.com
firebase deploy --only hosting
```

Your URL will be `https://<project-id>.web.app`. Put that in `NEST_CORS_ALLOWED_ORIGINS`
(Step 1) or nothing will load past the login screen.

---

## Option B - Cloudflare Pages (recommended)

Unlimited bandwidth on the free plan, which is the one that matters for a build this size.
Checked against Cloudflare's hard limits with the real build - all comfortable:

| Limit | Cloudflare | This build |
| --- | --- | --- |
| Max file size | 25 MiB | 6.9 MB (`canvaskit.wasm`) |
| Files per deploy | 20,000 | 41 |
| Build timeout | 20 min | ~4-6 min |

SPA routing is handled by `wrangler.jsonc` (`not_found_handling: "single-page-application"`), so it
needs no dashboard config.

> **Do not add a `_redirects` file with `/*  /index.html  200`.** That's the Pages/Netlify way and
> Workers Static Assets rejects it - the deploy fails with *"Infinite loop detected in this rule"*.
> `not_found_handling` already covers it. `web/_headers` (caching) is fine and is used.

### B1 - Auto-deploy from GitHub (set up once, then deploys on every push)

Dashboard → **Workers & Pages** → **Create** → **Pages** → **Connect to Git** → pick the repo, then:

- **Framework preset:** `None`
- **Build command:**
  ```
  git clone https://github.com/flutter/flutter.git --depth 1 -b stable $HOME/flutter && export PATH="$HOME/flutter/bin:$PATH" && cd NEST_FE && flutter pub get && flutter build web --release --dart-define=API_BASE_URL=https://owleodev.onrender.com
  ```
- **Build output directory:** `NEST_FE/build/web`
- **Root directory:** leave as the repo root (the command `cd`s itself)

Cloudflare's build image has no Flutter, hence the clone - `--depth 1` keeps it under a minute.

### B2 - Direct upload (deploy right now, no CI)

Faster to get working, and it uses no build minutes. You run the build locally:

```bash
npm install -g wrangler
wrangler login

cd NEST_FE
flutter build web --release --dart-define=API_BASE_URL=https://owleodev.onrender.com
wrangler pages deploy build/web --project-name=owleo-web
```

The first `deploy` offers to create the project. Repeat those last two commands for each release.

### Then, for either path

Your URL is `https://owleo-web.kalaapp2026.workers.dev`. **Add it to `NEST_CORS_ALLOWED_ORIGINS` on the backend**
(Step 1) - until you do, the site loads and every API call fails.

---

## Option C - Render static site (already configured)

`render.yaml` at the repo root already describes it. Either:

**Blueprint (recommended)** - Render dashboard → New → Blueprint → pick this repo. It reads
`render.yaml` and creates `owleo-web`. The file defines only the static site, never the backend,
so applying it cannot disturb the running API.

**Or by hand** - New → Static Site, connect the repo, then:

- **Build command:**
  ```
  git clone https://github.com/flutter/flutter.git --depth 1 -b stable $HOME/flutter && export PATH="$HOME/flutter/bin:$PATH" && cd NEST_FE && flutter pub get && flutter build web --release --dart-define=API_BASE_URL=https://owleodev.onrender.com
  ```
- **Publish directory:** `NEST_FE/build/web`
- **Redirect/Rewrite rule:** source `/*` → destination `/index.html`, type **Rewrite**

The rewrite is not optional. `go_router` uses real paths (`/login`, `/erp/courses`); without it,
refreshing on any page other than `/` returns 404.

First build takes ~3-6 minutes because it downloads Flutter. Later builds reuse the cache.

---

## Verify (any host)

1. Open `https://owleo-web.kalaapp2026.workers.dev`
2. Log in as `superadmin`
3. Open DevTools → Network. If you see CORS errors, Step 1 didn't apply.
4. Hard-refresh while on an inner page - it should reload, not 404 (that's the rewrite).

---

## The thing to know about "running every time"

**The web app is always up.** Static sites are CDN-served and never sleep.

**The backend is not**, on Render's free tier. It sleeps after ~15 minutes idle, and the next
request takes 30-60s to wake it while the JVM restarts. Users hitting it cold see a long pause or
a timeout on login.

Three honest options:

1. **Upgrade the backend to Render Starter (~$7/mo)** - no sleeping. This is the real fix if
   anyone outside your team uses the app.
2. **Keep-alive ping** - hit `/actuator/health` every ~10 minutes from an external cron
   (cron-job.org, UptimeRobot). Works, and stays within the ~750 free instance-hours a month if
   it's the only free service on the account - but a second free service would push you over, and
   Render may change this.
3. **Accept the cold start** - fine while it's just you testing.

Note the current free instance is also memory-capped at 512Mi, which the JVM flags in
`NEST_BE/Dockerfile` are tuned to fit (~400Mi under load). If you upgrade the plan, those caps
can be raised.

---

## Redeploying after changes

- **Backend:** push to `main` - Render rebuilds from the Dockerfile.
- **Web:** push to `main` - Render rebuilds the static site.

`API_BASE_URL` is compiled **into** the bundle by `--dart-define`, so changing the backend URL
means a **rebuild**, not a restart. Changing it in Render's env vars alone does nothing until the
site rebuilds.

## Android APK

Unrelated to the web deploy - build locally and distribute the file:

```bash
cd NEST_FE
flutter build apk --release --dart-define=API_BASE_URL=https://owleodev.onrender.com
# -> build/app/outputs/flutter-apk/app-release.apk
```
