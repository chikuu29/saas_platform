# Renderer Map

Use this file when deciding how a JSON template gets rendered in the workspace frontend.

## Entry Path

1. `apps/work_space/web/src/utils/app/HandleDynamicView.tsx`
   - Falls back to `WorkspacePage` when `AppRegistry` has no static React view for the requested route.
2. `apps/work_space/web/src/core/WorkspacePage.tsx`
   - Requests `app/ui_template` from the backend with `pageName` and `appName`.
3. `apps/work_space/web/src/core/renderer/ViewRenderer.tsx`
   - Reads `config.UI_TYPE.type`.
4. `apps/work_space/web/src/core/views/index.ts`
   - Resolves the matching view component through `ViewRegistry`.
5. `apps/work_space/web/src/core/renderer/RunTimeWidget.tsx`
   - Resolves nested widget configs through `WidgetRegistry`.

## Supported View Types

### `FORM_VIEW`

- React file: `apps/work_space/web/src/core/views/FormView.tsx`
- Expected schema: `config.UI_VIEW.schema.forms.tabs`
- Best for: standard forms, tabbed forms, submit flows, action buttons

### `SECTION_VIEW`

- React file: `apps/work_space/web/src/core/views/SectionView.tsx`
- Expected schema: `config.UI_VIEW.schema.sections`
- Best for: multi-step onboarding, wizards, section-by-section flows

### `GRID_VIEW`

- React file: `apps/work_space/web/src/core/views/GridView.tsx`
- Expected schema: `config.UI_VIEW.schema.grids` or `config.UI_VIEW.schema.components`
- Best for: dashboards, KPI layouts, table blocks, chart blocks, summary pages

### `PAGE_VIEW`

- React file: `apps/work_space/web/src/core/views/PageView.tsx`
- Expected schema: `config.UI_VIEW.schema.widgets`
- Best for: generic content pages and action-panel pages

## Registered Widget Keys

Source: `apps/work_space/web/src/core/widgets/index.ts`

- `textField`
- `radioField`
- `textAreaField`
- `uploadField`
- `panel`
- `grid`
- `stepper`
- `kpi`
- `kpiTable`
- `tabs`
- `dateField`
- `dateAndTimeField`
- `selectField`
- `switchField`
- `cardGrid`

If the requested widget is missing from this list, implement the widget in `src/core/widgets` and register it before using that key in JSON.
