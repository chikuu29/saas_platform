#!/bin/bash

# Usage: ./script.sh [up|down|restart|logs] [--detached]

ACTION="up"
DETACHED=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        up|down|restart|logs)
            ACTION="$1"
            shift
            ;;
        --detached)
            DETACHED=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [up|down|restart|logs] [--detached]"
            exit 1
            ;;
    esac
done

set -e

# Get the directory where the script is located
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="$ROOT/infra/dev/docker-compose.dev.yml"

if [ ! -f "$COMPOSE_FILE" ]; then
    echo "Error: Compose file not found: $COMPOSE_FILE"
    exit 1
fi

case $ACTION in
    "up")
        if [ "$DETACHED" = true ]; then
            docker compose -f "$COMPOSE_FILE" up --build -d
        else
            docker compose -f "$COMPOSE_FILE" up --build
        fi
        ;;
    "down")
        docker compose -f "$COMPOSE_FILE" down
        ;;
    "restart")
        docker compose -f "$COMPOSE_FILE" down
        if [ "$DETACHED" = true ]; then
            docker compose -f "$COMPOSE_FILE" up --build -d
        else
            docker compose -f "$COMPOSE_FILE" up --build
        fi
        ;;
    "logs")
        docker compose -f "$COMPOSE_FILE" logs -f
        ;;
esac