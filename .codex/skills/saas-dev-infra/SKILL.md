---
name: saas-dev-infra
description: Work on local development infrastructure for this repository. Use when updating Docker Compose files, docker-data mounts, PowerShell or batch helper scripts, root .gitignore rules, nested repo orchestration, local environment documentation, or infra/dev assets.
---

# SaaS Dev Infra

Use this skill for repo-level orchestration work rather than app business logic.

Primary areas:

- `infra/dev`
- `docker-data`
- root helper scripts
- root documentation
- root `.gitignore`
- root `.gitmodules`

## Workflow

1. Identify whether the task affects app runtime, data services, Docker paths, or repository tooling.
2. Prefer editing root orchestration files instead of duplicating logic inside app folders.
3. Keep local generated data under `docker-data/` and out of Git.
4. Use relative paths inside compose files so the repo stays portable.
5. Update docs when commands or folder expectations change.

## Repo rules

- Combined local stack lives in `infra/dev/docker-compose.dev.yml`.
- Data-only stack lives in `infra/dev/docker-compose.data.yml`.
- Mongo init script lives in `infra/dev/init-mongo.js`.
- Docker persistent data belongs under `docker-data/`.
- Root scripts include `start-dev.ps1`, `start-dev.bat`, `start-docker-dev.ps1`, and `sync-all-projects.ps1`.
- Read [references/dev-infra-map.md](references/dev-infra-map.md) for commands and file ownership.

## Validate

Use focused verification:

- `docker compose -f .\infra\dev\docker-compose.data.yml config`
- `docker compose -f .\infra\dev\docker-compose.dev.yml config`
- run the relevant PowerShell script with the intended action
