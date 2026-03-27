# LLM Workflow Guide

This document describes how to work in this repository with an LLM or coding agent.

## Choose the right area first

- Use `apps/identity_server/backend` for identity, OAuth, RBAC, organization, plans, PostgreSQL, and Redis work.
- Use `apps/identity_server/web` for auth and platform administration UI.
- Use `apps/work_space/backend` for workspace APIs, MongoDB-backed features, and storage-backed backend logic.
- Use `apps/work_space/web` for workspace product UI and feature modules.
- Use `infra/dev` and root scripts for Docker, orchestration, and local environment work.

## Recommended working order

1. Identify the owning app or root infra file.
2. Read nearby files before editing.
3. Make the smallest change that fits the existing structure.
4. Verify with the nearest command.
5. Update docs when commands, ports, paths, or workflows change.

## Repository-specific rules

- This root repo is an orchestration repo.
- The projects under `apps/` are nested Git repositories.
- Keep generated Docker data inside `docker-data/` and out of Git.
- Prefer root helper scripts when starting or syncing the full system.
- Prefer relative paths in Docker Compose files.

## Recommended skills

Repo-local skills live under [`.codex/skills`](d:/Development/saas_platform/.codex/skills):

- [`.codex/skills/saas-fastapi/SKILL.md`](d:/Development/saas_platform/.codex/skills/saas-fastapi/SKILL.md)
- [`.codex/skills/saas-frontend/SKILL.md`](d:/Development/saas_platform/.codex/skills/saas-frontend/SKILL.md)
- [`.codex/skills/saas-dev-infra/SKILL.md`](d:/Development/saas_platform/.codex/skills/saas-dev-infra/SKILL.md)

Use them when the task is clearly backend, frontend, or dev-infra focused.
