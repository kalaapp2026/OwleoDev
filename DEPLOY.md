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
| `NEST_CORS_ALLOWED_ORIGINS` | `https://owleo-web.onrender.com` |

Comma-separate if you add a custom domain later:
`https://owleo-web.onrender.com,https://app.owleonest.com`

Save - Render redeploys automatically. Confirm it took effect:

```bash
curl -s -D - -o /dev/null -X OPTIONS https://owleodev.onrender.com/auth/login \
  -H "Origin: https://owleo-web.onrender.com" \
  -H "Access-Control-Request-Method: POST" | grep -i access-control-allow-origin
```

You want a header back. Nothing means it isn't applied yet.

---

## Step 2 - Create the static site

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

## Step 3 - Verify

1. Open `https://owleo-web.onrender.com`
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
