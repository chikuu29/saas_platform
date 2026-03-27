---
name: saas-frontend
description: Work on the React frontends in this repository. Use when updating Vite apps, React pages, routes, shared UI components, feature modules, state slices, frontend environment variables, or frontend Docker/nginx setup inside apps/identity_server/web or apps/work_space/web.
---

# SaaS Frontend

Use this skill for frontend changes in:

- `apps/identity_server/web`
- `apps/work_space/web`

## Quick routing

- Use `apps/identity_server/web` for auth, organization, RBAC, OAuth management, and platform admin UI.
- Use `apps/work_space/web` for workspace UI, app rendering, feature modules, and identity-dependent product flows.

## Workflow

1. Find the owning feature, page, or route before editing shared UI.
2. Read the nearest `src/features`, `src/pages`, `src/core`, `src/components`, and config files.
3. Preserve existing visual patterns unless the task explicitly calls for redesign.
4. Check `vite.config.ts`, `.env` files, and nginx config when API paths or deployment behavior change.
5. Validate with the lightest relevant frontend command.

## Repo rules

- Both frontends use Vite + React.
- Identity frontend default dev port is `5174`.
- Workspace frontend default dev port is `5173`.
- Prefer feature-local edits over broad global changes.
- Read [references/frontend-map.md](references/frontend-map.md) when you need folder guidance or commands.

## Validate

Use the frontend app directory:

- `npm install` if dependencies are missing
- `npm run dev` for local verification
- `npm run build` for bundle-level verification when needed
