param(
    [ValidateSet("skip", "base", "strict", "active")]
    [string]$ExampleFolderMode = "skip",
    [switch]$Prune,
    [switch]$DryRun,
    [string]$MongoUri,
    [string]$DatabaseName
)

$backendDir = Join-Path $PSScriptRoot "apps\work_space\backend"
$pythonExe = Join-Path $backendDir ".venv\Scripts\python.exe"
$scriptPath = Join-Path $PSScriptRoot "infra\dev\sync-workspace-db-config.py"

if (-not (Test-Path $pythonExe)) {
    throw "Workspace backend virtualenv Python not found at $pythonExe"
}

$argsList = @($scriptPath, "--example-folder-mode", $ExampleFolderMode)

if ($Prune) {
    $argsList += "--prune"
}

if ($DryRun) {
    $argsList += "--dry-run"
}

if ($MongoUri) {
    $argsList += @("--mongo-uri", $MongoUri)
}

if ($DatabaseName) {
    $argsList += @("--db-name", $DatabaseName)
}

Push-Location $backendDir
try {
    & $pythonExe @argsList
    exit $LASTEXITCODE
}
finally {
    Pop-Location
}
