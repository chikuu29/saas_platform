# sync-mongo-to-cluster-workspace.ps1
# Run this from any directory — paths resolve relative to repo root via PSScriptRoot

# Repo root is 2 levels up from infra/gitops/
$repoRoot = (Resolve-Path "$PSScriptRoot\..\..")
Write-Host "Repo root: $repoRoot"

$pod = kubectl get pod -n workspace -l app=workspace-backend -o jsonpath='{.items[0].metadata.name}'
Write-Host "Syncing to pod: $pod"

# Create directory structure inside pod
kubectl exec -n workspace $pod -- mkdir -p /tmp/repo/infra/dev
kubectl exec -n workspace $pod -- mkdir -p /tmp/repo/apps/work_space/web

# Copy files using absolute paths from repo root
kubectl cp "$repoRoot\infra\dev\sync-workspace-db-config.py" workspace/${pod}:/tmp/repo/infra/dev/sync-workspace-db-config.py
kubectl cp "$repoRoot\apps\work_space\web\DB_CONFIG" workspace/${pod}:/tmp/repo/apps/work_space/web/DB_CONFIG

# Install missing Python dependencies inside the pod
Write-Host "Installing Python dependencies in pod..."
kubectl exec -n workspace $pod -- pip install python-dotenv pymongo --quiet

# Run the sync script with internal cluster MongoDB URI (no port-forward needed)
Write-Host "Running sync..."
kubectl exec -n workspace $pod -- python /tmp/repo/infra/dev/sync-workspace-db-config.py `
  --mongo-uri "mongodb://workspace_admin:admin123@workspace-mongodb:27017/workspace_db?authSource=admin" `
  --db-name workspace_db

Write-Host "Done!"
