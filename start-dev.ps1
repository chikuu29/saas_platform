param(
    [switch]$Here
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path

$projects = @(
    @{
        Name = "identity-backend"
        Path = Join-Path $root "apps\identity_server\backend"
        InstallCommand = "uv sync"
        DependencyPath = ".venv"
        Command = "uv run uvicorn app.main:app --port 8000 --reload"
    },
    @{
        Name = "identity-web"
        Path = Join-Path $root "apps\identity_server\web"
        InstallCommand = "npm install"
        DependencyPath = "node_modules"
        Command = "npm run dev"
    },
    @{
        Name = "workspace-backend"
        Path = Join-Path $root "apps\work_space\backend"
        InstallCommand = "uv sync"
        DependencyPath = ".venv"
        Command = "uv run uvicorn app.main:app --port 8001 --reload"
    },
    @{
        Name = "workspace-web"
        Path = Join-Path $root "apps\work_space\web"
        InstallCommand = "npm install"
        DependencyPath = "node_modules"
        Command = "pnpm dev"
    }
)

function Ensure-Dependencies {
    param(
        [hashtable]$Project
    )

    $dependencyFullPath = Join-Path $Project.Path $Project.DependencyPath
    if (Test-Path $dependencyFullPath) {
        Write-Host "Dependencies already present for $($Project.Name)"
        return
    }

    Write-Host "Installing missing dependencies for $($Project.Name)..."
    Push-Location $Project.Path
    try {
        Invoke-Expression $Project.InstallCommand
    }
    finally {
        Pop-Location
    }
}

if ($Here) {
    foreach ($project in $projects) {
        if (-not (Test-Path $project.Path)) {
            Write-Warning "Skipping $($project.Name): path not found: $($project.Path)"
            continue
        }

        Ensure-Dependencies -Project $project

        Write-Host "Starting $($project.Name) in the current terminal..."
        Push-Location $project.Path
        try {
            Invoke-Expression $project.Command
        }
        finally {
            Pop-Location
        }
    }

    return
}

$startedProcesses = @()

Write-Host "Starting Development Environment..."

foreach ($project in $projects) {
    if (-not (Test-Path $project.Path)) {
        Write-Warning "Skipping $($project.Name): path not found: $($project.Path)"
        continue
    }

    Ensure-Dependencies -Project $project

    $windowCommand = @"
`$Host.UI.RawUI.WindowTitle = '$($project.Name)'
Set-Location '$($project.Path)'
$($project.Command)
"@

    $process = Start-Process powershell.exe -ArgumentList @(
        "-NoExit",
        "-Command",
        $windowCommand
    ) -PassThru

    $startedProcesses += [PSCustomObject]@{
        Name = $project.Name
        ProcessId = $process.Id
    }
}

Write-Host ""
Write-Host "Press any key to stop all services..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

foreach ($process in $startedProcesses) {
    try {
        Stop-Process -Id $process.ProcessId -Force -ErrorAction Stop
        Write-Host "Stopped $($process.Name)"
    }
    catch {
        Write-Warning "Could not stop $($process.Name). It may have already exited."
    }
}

Write-Host "All services stopped."
