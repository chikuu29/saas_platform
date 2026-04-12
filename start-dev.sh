#!/bin/bash

# Usage: ./start-dev.sh [--here]

HERE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --here)
            HERE=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--here]"
            exit 1
            ;;
    esac
done

set -e

# Get the directory where the script is located
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Define projects as arrays
PROJECT_NAMES_ARRAY=()
PROJECT_PATHS=()
PROJECT_INSTALL_COMMANDS=()
PROJECT_DEPENDENCY_PATHS=()
PROJECT_COMMANDS=()

# Function to add a project
add_project() {
    local name="$1"
    local path="$2"
    local install_cmd="$3"
    local dep_path="$4"
    local cmd="$5"
    
    PROJECT_NAMES_ARRAY+=("$name")
    PROJECT_PATHS+=("$path")
    PROJECT_INSTALL_COMMANDS+=("$install_cmd")
    PROJECT_DEPENDENCY_PATHS+=("$dep_path")
    PROJECT_COMMANDS+=("$cmd")
}

# Define projects
add_project "identity-backend" \
    "$ROOT/apps/identity_server/backend" \
    "uv sync" \
    ".venv" \
    "uv run uvicorn app.main:app --port 8000 --reload"

add_project "identity-web" \
    "$ROOT/apps/identity_server/web" \
    "npm install" \
    "node_modules" \
    "npm run dev"

add_project "workspace-backend" \
    "$ROOT/apps/work_space/backend" \
    "uv sync" \
    ".venv" \
    "uv run uvicorn app.main:app --port 8001 --reload"

add_project "workspace-web" \
    "$ROOT/apps/work_space/web" \
    "npm install" \
    "node_modules" \
    "npm run dev"

# Function to ensure dependencies are installed
ensure_dependencies() {
    local index=$1
    local name="${PROJECT_NAMES_ARRAY[$index]}"
    local path="${PROJECT_PATHS[$index]}"
    local install_cmd="${PROJECT_INSTALL_COMMANDS[$index]}"
    local dep_path="${PROJECT_DEPENDENCY_PATHS[$index]}"
    
    local dependency_full_path="$path/$dep_path"
    
    if [ -d "$dependency_full_path" ]; then
        echo "✓ Dependencies already present for $name"
        return 0
    fi
    
    echo "📦 Installing missing dependencies for $name..."
    (cd "$path" && eval "$install_cmd")
    echo "✓ Dependencies installed for $name"
}

# Function to start all services in separate terminal windows (macOS)
start_all_services() {
    local pids_file="/tmp/dev_services_pids.txt"
    > "$pids_file"
    
    echo "🚀 Starting Development Environment..."
    echo ""
    
    for i in "${!PROJECT_NAMES_ARRAY[@]}"; do
        local name="${PROJECT_NAMES_ARRAY[$i]}"
        local path="${PROJECT_PATHS[$i]}"
        local cmd="${PROJECT_COMMANDS[$i]}"
        
        if [ ! -d "$path" ]; then
            echo "⚠️  Warning: Skipping $name: path not found: $path"
            continue
        fi
        
        ensure_dependencies "$i"
        
        echo "▶️  Starting $name..."
        
        # Escape single quotes in the command
        local cmd_escaped="${cmd//\'/\'\"\'\"\'}"
        
        # Create an AppleScript to open a new terminal window and run the command
        osascript <<EOF &
tell application "Terminal"
    set newWindow to do script "cd '$path' && clear && echo '═══════════════════════════════════════' && echo '  Starting: $name' && echo '═══════════════════════════════════════' && echo '' && $cmd_escaped"
    set custom title of newWindow to "$name"
end tell
EOF
        
        # Store the PID of the osascript process
        echo "$!" >> "$pids_file"
        
        # Give the terminal time to open
        sleep 1.5
    done
    
    echo ""
    echo "═══════════════════════════════════════"
    echo "✅ All services started!"
    echo "═══════════════════════════════════════"
    echo ""
    echo "Press ENTER to stop all services..."
    read -r
    
    # Kill all osascript processes (which will close the terminals)
    if [ -f "$pids_file" ]; then
        while read -r pid; do
            kill "$pid" 2>/dev/null
        done < "$pids_file"
        rm "$pids_file"
    fi
    
    # Also try to kill the actual service processes
    for i in "${!PROJECT_NAMES_ARRAY[@]}"; do
        local name="${PROJECT_NAMES_ARRAY[$i]}"
        local cmd="${PROJECT_COMMANDS[$i]}"
        
        # Extract the main command (first part before spaces)
        local main_cmd=$(echo "$cmd" | awk '{print $1}')
        
        # Kill processes by port for backend services
        if [[ "$cmd" == *"uvicorn"* ]]; then
            if [[ "$cmd" == *"8000"* ]]; then
                lsof -ti:8000 | xargs kill -9 2>/dev/null && echo "✓ Stopped $name (port 8000)"
            elif [[ "$cmd" == *"8001"* ]]; then
                lsof -ti:8001 | xargs kill -9 2>/dev/null && echo "✓ Stopped $name (port 8001)"
            fi
        else
            # For web services (npm)
            pkill -f "npm run dev" 2>/dev/null && echo "✓ Stopped $name"
        fi
    done
    
    echo ""
    echo "🛑 All services stopped."
}

# Function to run services in current terminal (one at a time)
run_here() {
    echo "🚀 Starting services in current terminal..."
    echo ""
    echo "⚠️  Services will run one after another."
    echo "⚠️  Press Ctrl+C to stop the current service and move to the next."
    echo ""
    read -p "Press ENTER to continue..."
    
    for i in "${!PROJECT_NAMES_ARRAY[@]}"; do
        local name="${PROJECT_NAMES_ARRAY[$i]}"
        local path="${PROJECT_PATHS[$i]}"
        
        if [ ! -d "$path" ]; then
            echo "⚠️  Warning: Skipping $name: path not found: $path"
            continue
        fi
        
        ensure_dependencies "$i"
        
        echo ""
        echo "═══════════════════════════════════════"
        echo "▶️  Starting $name..."
        echo "═══════════════════════════════════════"
        echo ""
        echo "Press Ctrl+C when done to continue to next service"
        echo ""
        
        (cd "$path" && eval "${PROJECT_COMMANDS[$i]}")
        
        echo ""
        echo "✓ Stopped $name"
        echo ""
    done
    
    echo "✅ All services have been run."
}

# Main execution
if [ "$HERE" = true ]; then
    run_here
else
    start_all_services
fi