# SaaS Platform Monorepo

This repository is the parent workspace for two application groups:

- `identity_server`: authentication, OAuth, RBAC, plans, and platform services
- `work_space`: the product/workspace application that depends on the identity server

The root repository mainly organizes infrastructure, shared developer scripts, and local environment setup. Each app inside `apps/` is its own Git repository.

## Project Structure

```text
saas_platform/
|-- .github/                      # GitHub workflows, issue templates, repo automation
|-- apps/
|   |-- identity_server/
|   |   |-- backend/             # FastAPI identity service, PostgreSQL, Redis integration
|   |   `-- web/                 # Vite + React identity frontend
|   `-- work_space/
|       |-- backend/             # FastAPI workspace service, MongoDB integration
|       `-- web/                 # Vite + React workspace frontend
|-- docker-data/                 # Local Docker volume data kept outside app source trees
|   |-- identity-server/
|   |   |-- logs/                # Identity container log mounts
|   |   |-- postgres/            # Identity PostgreSQL persistent data
|   |   `-- redis/               # Identity Redis persistent data
|   `-- workspace/
|       `-- mongodb/             # Workspace MongoDB persistent data
|-- docs/                        # Repository-level documentation
|-- infra/
|   |-- cloud/                   # Cloud/deployment infrastructure files
|   `-- dev/                     # Local Docker Compose files and dev infra helpers
|-- start-dev.bat                # Starts all 4 apps in separate cmd windows
|-- start-dev.ps1                # Starts all 4 apps in separate PowerShell windows
|-- start-docker-dev.ps1         # Starts/stops the combined Docker dev stack
|-- sync-all-projects.ps1        # Fetches/pulls all nested app repositories
|-- .gitignore                   # Root ignore rules for the parent repo
`-- .gitmodules                  # Submodule config reference for nested repos
```

## Folder Purpose

### Root folders

- `.github/`
  Used for GitHub Actions, CI/CD workflows, templates, and repository automation.

- `apps/`
  Contains the actual product applications. These are the main codebases you work on.

- `docker-data/`
  Stores local database and service data used by Docker. This is intentionally ignored by Git except for `.gitkeep` placeholders.
  Generated files inside this folder should stay local and must not be pushed to GitHub.

- `docs/`
  Intended for repository-level documentation such as architecture notes, onboarding, environment setup, or runbooks.

- `infra/`
  Holds infrastructure-related files. `infra/dev` is for local Docker/dev environment files. `infra/cloud` is for cloud or deployment-specific infra later.

### App folders

- `apps/identity_server/backend/`
  Identity backend service built with FastAPI.
  Main responsibilities:
  PostgreSQL-backed identity data, OAuth flows, RBAC, plans, org management, Redis-backed sessions/rate limits.

- `apps/identity_server/web/`
  Identity admin/auth frontend built with Vite + React.
  Main responsibilities:
  login flows, organization setup, access control UI, OAuth/client management, platform admin views.

- `apps/work_space/backend/`
  Workspace backend service built with FastAPI.
  Main responsibilities:
  workspace APIs, app/module logic, MongoDB integration, storage/static files, workspace domain features.

- `apps/work_space/web/`
  Workspace frontend built with Vite + React.
  Main responsibilities:
  workspace UI, app rendering, auth callback flows, dynamic views, feature modules.

## Important Subfolders Inside Apps

### `identity_server/backend`

- `app/`
  Main FastAPI application code.

- `alembic/`
  Database migration scripts for PostgreSQL.

- `setup/`
  Setup utilities, DB scripts, and older Docker-related files.

- `tests/`
  API, unit, and service-level tests.

- `keys/`
  Local key material used by the identity service.

- `logs/`
  Local backend log output.

### `identity_server/web`

- `src/`
  Frontend source code.

- `public/`
  Public static assets.

- `nginx/`
  Nginx config used by Docker image builds.

- `DB_CONFIG/`
  UI/view configuration JSON files.

- `plugin/`
  Custom Vite/plugin helpers.

### `work_space/backend`

- `app/`
  Main FastAPI application code.

- `storage/`
  Local uploaded/generated files exposed by the backend.

- `logs/`
  Local backend logs.

### `work_space/web`

- `src/`
  Frontend source code.

- `public/`
  Public assets used at runtime.

- `DB_CONFIG/`
  Workspace view and feature configuration JSON files.

- `nginx/`
  Nginx config used by the Docker image.

- `plugin/`
  Custom Vite/plugin helpers.

## Local Development

### Start all 4 apps directly

```powershell
.\start-dev.ps1
```

Batch alternative:

```bat
.\start-dev.bat
```

### Start all services with Docker

```powershell
.\start-docker-dev.ps1 up
```

Other Docker commands:

```powershell
.\start-docker-dev.ps1 down
.\start-docker-dev.ps1 restart
.\start-docker-dev.ps1 logs
```

### Sync all nested app repositories

```powershell
.\sync-all-projects.ps1
```

## Notes

- The root repo is an orchestration repository, not the main application codebase.
- The projects under `apps/` are nested Git repositories.
- Docker persistent data lives under `docker-data/` so local DB files do not mix with source code.
- Only folder placeholders such as `.gitkeep` should be tracked inside `docker-data/`. Generated database files, Redis data, logs, and other runtime artifacts should remain untracked.
