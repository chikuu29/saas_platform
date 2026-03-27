# Backend Map

## Identity backend

- Path: `apps/identity_server/backend`
- Stack: FastAPI + PostgreSQL + Redis
- Entrypoint: `app.main:app`
- Dev port: `8000`
- Key folders:
  - `app/`
  - `alembic/`
  - `tests/`
  - `setup/`

## Workspace backend

- Path: `apps/work_space/backend`
- Stack: FastAPI + MongoDB
- Entrypoint: `app.main:app`
- Dev port: `7000`
- Key folders:
  - `app/`
  - `storage/`
  - `logs/`

## Useful commands

```powershell
cd apps\identity_server\backend
uv sync
uv run uvicorn app.main:app --port 8000 --reload
```

```powershell
cd apps\work_space\backend
uv sync
uv run uvicorn app.main:app --port 7000 --reload
```
