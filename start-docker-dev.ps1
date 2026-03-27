param(
    [ValidateSet("up", "down", "restart", "logs")]
    [string]$Action = "up",
    [switch]$Detached
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$composeFile = Join-Path $root "infra\dev\docker-compose.dev.yml"

if (-not (Test-Path $composeFile)) {
    throw "Compose file not found: $composeFile"
}

switch ($Action) {
    "up" {
        if ($Detached) {
            docker compose -f $composeFile up --build -d
        }
        else {
            docker compose -f $composeFile up --build
        }
    }
    "down" {
        docker compose -f $composeFile down
    }
    "restart" {
        docker compose -f $composeFile down
        if ($Detached) {
            docker compose -f $composeFile up --build -d
        }
        else {
            docker compose -f $composeFile up --build
        }
    }
    "logs" {
        docker compose -f $composeFile logs -f
    }
}
