# sync-mongo-to-cluster-workspace.ps1
# Run this from any directory — paths resolve relative to repo root via PSScriptRoot

# Repo root is 2 levels up from infra/gitops/
$repoRootRaw = (Resolve-Path "$PSScriptRoot\..\..")
$repoRoot = $repoRootRaw.ProviderPath
Write-Host "Repo root: $repoRoot"

$pod = kubectl get pod -n workspace -l app=workspace-backend -o jsonpath='{.items[0].metadata.name}'
Write-Host "Syncing to pod: $pod"

# Create directory structure and venv inside pod
Write-Host "Preparing pod environment..."
kubectl exec -n workspace $pod -- mkdir -p /tmp/repo/infra/dev
kubectl exec -n workspace $pod -- mkdir -p /tmp/repo/apps/work_space/web
kubectl exec -n workspace $pod -- python -m venv /tmp/venv

# Save current location and move to repo root to use relative paths (fixes kubectl cp colon issues on Windows)
$oldLocation = Get-Location
Set-Location $repoRoot

# Copy files using relative paths
Write-Host "Copying files to pod..."
kubectl cp "infra/dev/sync-workspace-db-config.py" "${pod}:/tmp/repo/infra/dev/" -n workspace
kubectl cp "apps/work_space/web/DB_CONFIG" "${pod}:/tmp/repo/apps/work_space/web/" -n workspace

# Restore location
Set-Location $oldLocation

# Install missing Python dependencies inside the venv
Write-Host "Installing Python dependencies in venv..."
kubectl exec -n workspace $pod -- /tmp/venv/bin/pip install --upgrade pip --quiet
kubectl exec -n workspace $pod -- /tmp/venv/bin/pip install python-dotenv pymongo --quiet

# Run the sync script using the venv python
Write-Host "Running sync..."
kubectl exec -n workspace $pod -- /tmp/venv/bin/python /tmp/repo/infra/dev/sync-workspace-db-config.py `
  --mongo-uri "mongodb://workspace_admin:admin123@workspace-mongodb:27017/workspace_db?authSource=admin" `
  --db-name workspace_db

Write-Host "Done!"
