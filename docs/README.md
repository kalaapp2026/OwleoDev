# NEST documentation set

| File | For | What |
|---|---|---|
| [`../CLAUDE.md`](../CLAUDE.md) | developers + Claude | run commands, traps, settled conventions, current state |
| [ARCHITECTURE.md](ARCHITECTURE.md) | developers + Claude | repo map, back-end domains, roles/RBAC, front-end structure, deployment |
| [DATA_DIRECTORY.md](DATA_DIRECTORY.md) | developers + Claude | every table by domain, where files/backups/secrets live, what is safe to share |
| [USER_MANUAL.md](USER_MANUAL.md) | academy admins, trainers, students | how to use each module |
| [`../.claude/skills/`](../.claude/skills) | Claude Code | `nest-onboarding`, `nest-rbac-scoping`, `nest-flutter-ui`, `nest-db-migration`, `nest-run-and-verify`, `nest-deploy` |

## Handing the project to someone (or to their Claude)

1. Share the repo **without**: `db_backups/`, `uploads/`, secrets, `hs_err_pid*.log`, `replay_pid*.log`,
   `*.apk`, `build/`, `target/`. (A zip of the tree with those excluded, or a git remote.)
2. They open the folder in Claude Code. `CLAUDE.md` loads automatically and the skills in
   `.claude/skills/` become available; tell it: *"Read CLAUDE.md and docs/, then use the
   nest-onboarding skill."*
3. For realistic data, give them a schema-only dump or a seeded dev database
   (see DATA_DIRECTORY.md), not production rows.
4. Your personal Claude memory (`C:\Users\vishruth\.claude\projects\d--NEST\memory\`) does not travel
   with the repo; everything that matters from it is in `CLAUDE.md`.
