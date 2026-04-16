$ErrorActionPreference = 'Stop'

Write-Host "🔐 Downloading and Setting Up kubeseal..." -ForegroundColor Cyan

# Download kubeseal locally
$version = "0.27.1"
$url = "https://github.com/bitnami-labs/sealed-secrets/releases/download/v$version/kubeseal-$version-windows-amd64.tar.gz"

if (-not (Test-Path ".\kubeseal.exe")) {
    Invoke-WebRequest -Uri $url -OutFile "kubeseal.tar.gz"
    tar -xzf kubeseal.tar.gz kubeseal.exe
    Remove-Item kubeseal.tar.gz
}

Write-Host "🔐 Generating and Sealing Database Secrets..." -ForegroundColor Cyan

# ==========================================
# 1. Identity PostgreSQL Secret
# ==========================================
Write-Host "-> Sealing Identity PostgreSQL Secret..." -ForegroundColor Yellow

$postgresUser = "postgres"
$postgresPass = "password"
$postgresDb = "identity_provider_database"
$postgresUrl = "postgresql+asyncpg://${postgresUser}:${postgresPass}@identity-postgres:5432/${postgresDb}"

kubectl create secret generic identity-postgres-secret `
  --namespace identity `
  --from-literal=POSTGRES_USER=$postgresUser `
  --from-literal=POSTGRES_PASSWORD=$postgresPass `
  --from-literal=DATABASE_URL=$postgresUrl `
  --dry-run=client -o yaml > temp-postgres-secret.yaml

.\kubeseal.exe --controller-name=sealed-secrets-controller `
  --controller-namespace=kube-system `
  --format yaml -f temp-postgres-secret.yaml > "infra\gitops\infra\identity-postgres\sealed-secret.yaml"

Remove-Item temp-postgres-secret.yaml


# ==========================================
# 2. Workspace MongoDB Secret
# ==========================================
Write-Host "-> Sealing Workspace MongoDB Secret..." -ForegroundColor Yellow

$mongoUser = "workspace_admin"
$mongoPass = "admin123"
$mongoDb = "workspace_db"
$mongoUrl = "mongodb://${mongoUser}:${mongoPass}@workspace-mongodb:27017/${mongoDb}?authSource=admin"

kubectl create secret generic workspace-mongodb-secret `
  --namespace workspace `
  --from-literal=MONGO_INITDB_ROOT_USERNAME=$mongoUser `
  --from-literal=MONGO_INITDB_ROOT_PASSWORD=$mongoPass `
  --from-literal=MONGO_URI=$mongoUrl `
  --dry-run=client -o yaml > temp-mongo-secret.yaml

.\kubeseal.exe --controller-name=sealed-secrets-controller `
  --controller-namespace=kube-system `
  --format yaml -f temp-mongo-secret.yaml > "infra\gitops\infra\workspace-mongodb\sealed-secret.yaml"

Remove-Item temp-mongo-secret.yaml


Write-Host ""
Write-Host "✅ Success! Both secrets have been sealed successfully." -ForegroundColor Green
Write-Host "I updated the YAML files with the real secure encrypted data." -ForegroundColor White
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. git add infra\gitops\infra"
Write-Host "  2. git commit -m `"chore: seal database secrets`""
Write-Host "  3. git push"
Write-Host ""
