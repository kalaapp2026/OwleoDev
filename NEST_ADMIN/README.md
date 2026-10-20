# Owleo HQ Console

The platform super admin's web app: a Flutter project on the same Spring Boot backend and login as the
academy app. See [PLAN.md](PLAN.md) for how to run it, the module map, roles, what is not built yet, and
the traps found while building it.

```bash
flutter pub get
flutter run -d web-server --release --web-hostname 0.0.0.0 --web-port 5100
flutter test
```

Sign in as `superadmin` / `SuperAdmin@123` against a backend on port 8081 (override with
`--dart-define=API_BASE_URL=...`).
