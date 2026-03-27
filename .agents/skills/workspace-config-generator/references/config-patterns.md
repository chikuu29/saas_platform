# Config Patterns

Use these patterns as a base. Prefer copying the nearest real template from `apps/work_space/web/DB_CONFIG/TEMPLATE` and then adapting it.

## Shared Shell

Most page templates should keep these top-level fields aligned:

```json
{
  "pageName": "AddMember",
  "route": "AddMember",
  "appName": "myGym",
  "appMeta": {
    "appName": "Gym",
    "viewName": "AddMember"
  },
  "UI_TYPE": {
    "type": "FORM_VIEW",
    "title": "Create New Member",
    "description": ""
  },
  "UI_VIEW": {
    "schema": {}
  }
}
```

## Form View

`FORM_VIEW` must feed `UI_VIEW.schema.forms.tabs` because `FormView.tsx` reads that exact path.

```json
{
  "UI_TYPE": {
    "type": "FORM_VIEW",
    "title": "Create New Member"
  },
  "UI_VIEW": {
    "schema": {
      "forms": {
        "tabs": [
          {
            "name": "basicInfo",
            "label": "Basic Info",
            "widgets": [
              {
                "name": "memberName",
                "text": "Member Name",
                "widget": "textField",
                "required": true
              }
            ]
          }
        ]
      }
    }
  }
}
```

## Section View

`SECTION_VIEW` must feed `UI_VIEW.schema.sections`.

```json
{
  "UI_TYPE": {
    "type": "SECTION_VIEW",
    "title": "Member Onboarding"
  },
  "UI_VIEW": {
    "schema": {
      "sections": [
        {
          "title": "Profile",
          "widgets": [
            {
              "name": "memberName",
              "widget": "textField"
            }
          ]
        }
      ]
    }
  }
}
```

## Grid View

`GRID_VIEW` must feed `UI_VIEW.schema.grids` or `UI_VIEW.schema.components`.

```json
{
  "UI_TYPE": {
    "type": "GRID_VIEW",
    "title": "Gym Dashboard"
  },
  "UI_VIEW": {
    "schema": {
      "grids": [
        {
          "id": "members-kpi",
          "UI_TYPE": "KPI_SECTION",
          "layout": {
            "gridColumn": "1 / -1"
          },
          "widgets": [
            {
              "name": "totalMembers",
              "widget": "kpi",
              "label": "Total Members",
              "value": "1204"
            }
          ]
        }
      ]
    }
  }
}
```

## Page View

`PAGE_VIEW` must feed `UI_VIEW.schema.widgets`.

```json
{
  "UI_TYPE": {
    "type": "PAGE_VIEW",
    "title": "Workspace Tools"
  },
  "UI_VIEW": {
    "schema": {
      "widgets": [
        {
          "name": "quickActions",
          "widget": "cardGrid"
        }
      ]
    }
  }
}
```

## App Navigation Config

Use `apps/work_space/web/DB_CONFIG/APP_CONFIG/appNavConfig.json` for app list and menu definitions.

- `config.appList`: launcher tiles
- `config.featueListBaseOnURL.<app>.MENU`: side navigation entries
- Menu items can use `path` for route navigation or `action.type = "modal"` to open a template-backed dialog

## Real Source Templates

- `apps/work_space/web/DB_CONFIG/TEMPLATE/exmple/exmple.json`
- `apps/work_space/web/DB_CONFIG/TEMPLATE/exmple/formView.json`
- `apps/work_space/web/DB_CONFIG/TEMPLATE/exmple/gridView.json`
- `apps/work_space/web/DB_CONFIG/TEMPLATE/exmple/sectionView.json`
- `apps/work_space/web/DB_CONFIG/TEMPLATE/GYM/addMember.json`
- `apps/work_space/web/DB_CONFIG/TEMPLATE/GYM/addTrainer.json`
- `apps/work_space/web/DB_CONFIG/TEMPLATE/GYM/gymDashboard.json`
