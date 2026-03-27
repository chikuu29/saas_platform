# Dev Infra Map

## Main files

- `infra/dev/docker-compose.dev.yml`
  Combined local stack for both apps and their backing data services.

- `infra/dev/docker-compose.data.yml`
  Data-only local stack for PostgreSQL, Redis, MongoDB, and mongo-express.

- `infra/dev/init-mongo.js`
  Mongo bootstrap script for local workspace development.

- `start-dev.ps1`
  Starts all four app dev servers directly.

- `start-dev.bat`
  Batch equivalent for starting the four app dev servers.

- `start-docker-dev.ps1`
  Wrapper for the combined Docker stack with `up`, `down`, `restart`, and `logs`.

- `sync-all-projects.ps1`
  Fetches and pulls the nested app repositories safely.

## Data directories

- `docker-data/identity-server/postgres`
- `docker-data/identity-server/redis`
- `docker-data/identity-server/logs`
- `docker-data/workspace/mongodb`

Only `.gitkeep` placeholders should be tracked there.

## Useful commands

```powershell
docker compose -f .\infra\dev\docker-compose.data.yml up -d
docker compose -f .\infra\dev\docker-compose.dev.yml up --build
.\start-docker-dev.ps1 up -Detached
.\start-docker-dev.ps1 down
.\sync-all-projects.ps1
```
