---
name: workspace-config-generator
description: Generate, extend, and troubleshoot config-driven workspace pages for this repository. Use when Codex needs to create or update JSON under apps/work_space/web/DB_CONFIG, choose the correct UI_TYPE for a frontend-rendered page, wire page/menu config to the workspace renderer, or determine when a new widget/view must also be registered in the React frontend.
---

# Workspace Config Generator

Build JSON configs that the workspace frontend can render through `WorkspacePage`, `ViewRenderer`, `ViewRegistry`, and `WidgetRegistry`. Prefer this skill for page templates, modal templates, dashboards, form flows, and app navigation config inside `apps/work_space/web/DB_CONFIG`.

## Workflow

1. Identify the target config file before editing.
   - Use `apps/work_space/web/DB_CONFIG/APP_CONFIG/appNavConfig.json` for app launcher and left-nav menu definitions.
   - Use `apps/work_space/web/DB_CONFIG/TEMPLATE/<app>/<page>.json` for page, dialog, form, dashboard, and section templates.
2. Match the page to a real renderer contract.
   - Read `references/renderer-map.md` to map `UI_TYPE.type` to the frontend view component.
   - Read `references/config-patterns.md` to see the minimum JSON shape for each supported view type.
3. Start from the nearest existing template instead of inventing a schema.
   - Copy the closest file in `DB_CONFIG/TEMPLATE`.
   - Keep `appName`, `pageName`, `route`, and `appMeta.viewName` aligned.
   - Reuse existing widget keys whenever possible.
4. Escalate from JSON to React code only when necessary.
   - If the requested widget key is not registered, add the widget component and register it in `apps/work_space/web/src/core/widgets/index.ts`.
   - If the requested `UI_TYPE.type` does not exist, add a view component and register it in `apps/work_space/web/src/core/views/index.ts`.
   - If the page should be a static React screen instead of config-driven, register it through `apps/work_space/web/src/core/registry/AppRegistry.ts` rather than `DB_CONFIG`.

## Rules

- Keep `UI_TYPE.type` present and valid. The current frontend supports `FORM_VIEW`, `SECTION_VIEW`, `GRID_VIEW`, and `PAGE_VIEW`.
- Match the schema container to the selected view type. Do not mix `forms.tabs`, `sections`, `grids`, and `widgets` blindly.
- Use registered widget names only unless you are also updating the frontend registry.
- Keep actions and listeners realistic. Do not reference handler names, events, or scripts that do not exist in the surrounding feature.
- Prefer adding fields incrementally to an existing working template over generating a large config from scratch.
- Preserve existing naming and casing conventions in the target app folder, even if they are inconsistent.

## Validation

- Confirm the file sits in the correct `APP_CONFIG` or `TEMPLATE` location.
- Re-check the selected view contract against `references/renderer-map.md`.
- Re-check widget names against `apps/work_space/web/src/core/widgets/index.ts`.
- Re-check view names against `apps/work_space/web/src/core/views/index.ts`.
- If you changed frontend code, validate from `apps/work_space/web` with `npx tsc --noEmit`.

## Resources

- `references/renderer-map.md`: frontend rendering pipeline, file map, and view-to-schema contract.
- `references/config-patterns.md`: minimal JSON patterns for nav config, form pages, section flows, dashboards, and page views.
