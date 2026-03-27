---
name: saas-fastapi
description: Work on the FastAPI backends in this repository. Use when updating Python API code, routes, schemas, services, middleware, database integration, environment configuration, Dockerfiles, or tests inside apps/identity_server/backend or apps/work_space/backend.
---

# SaaS FastAPI

Use this skill for backend changes in:

- `apps/identity_server/backend`
- `apps/work_space/backend`

## Quick routing

- Use `apps/identity_server/backend` for identity, OAuth, RBAC, plans, organizations, Redis-backed sessions, and PostgreSQL-backed flows.
- Use `apps/work_space/backend` for workspace APIs, MongoDB-backed modules, storage, and workspace feature logic.

## Workflow

1. Confirm which backend owns the feature or bug.
2. Read the nearest router, service, repository, schema, and config files before editing.
3. Preserve the existing architectural split.
4. Update env, Docker, or tests when startup or persistence changes.
5. Verify with the smallest useful command for the touched service.

## Repo rules

- Prefer `uv run ...` for Python commands.
- Identity backend entrypoint is `app.main:app` on port `8000`.
- Workspace backend entrypoint is `app.main:app` on port `7000`.
- Identity backend uses PostgreSQL and Redis.
- Workspace backend uses MongoDB.
- Read [references/backend-map.md](references/backend-map.md) when you need folder guidance or commands.

## Validate

Prefer narrow validation:

- `uv run uvicorn app.main:app --port 8000 --reload`
- `uv run uvicorn app.main:app --port 7000 --reload`
- targeted pytest commands when tests exist
