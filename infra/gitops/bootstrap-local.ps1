# Bootstrap - Local Kubernetes + ArgoCD + SaaS Platform
# Run this script once to set up the full local production environment.
# Prerequisites: Docker Desktop running, winget available.
#
# Usage (run as Administrator in PowerShell):
#   Set-ExecutionPolicy Bypass -Scope Process
#   .\infra\gitops\bootstrap-local.ps1

param(
    [string]$DockerHubUsername = "cchiku1999",
    [string]$GithubRepo       = "https://github.com/chikuu29/saas_platform.git",
    [string]$ClusterName      = "saas-local"
)

$ErrorActionPreference = "Stop"

Write-Host "`n============================================================" -ForegroundColor Cyan
Write-Host " SaaS Platform - Local K8s Bootstrap" -ForegroundColor Cyan
Write-Host "============================================================`n" -ForegroundColor Cyan

# -- Step 1: Install CLI tools -------------------------------------------------

function Install-IfMissing([string]$cmd, [string]$wingetId) {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
        Write-Host "Installing $cmd..." -ForegroundColor Yellow
        winget install --id $wingetId -e --silent
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    } else {
        Write-Host "[OK] $cmd already installed" -ForegroundColor Green
    }
}

Install-IfMissing "k3d"      "k3d.k3d"
Install-IfMissing "kubectl"  "Kubernetes.kubectl"
Install-IfMissing "helm"     "Helm.Helm"
Install-IfMissing "argocd"   "argoproj.argocd"

# kubeseal must be downloaded manually - check if present
if (-not (Get-Command "kubeseal" -ErrorAction SilentlyContinue)) {
    Write-Host ""
    Write-Warning "kubeseal not found. Download from:"
    Write-Warning "  https://github.com/bitnami-labs/sealed-secrets/releases"
    Write-Warning "  Place kubeseal.exe in your PATH before sealing secrets."
}

# -- Step 2: Create k3d cluster ------------------------------------------------

Write-Host "`n[2/7] Creating k3d cluster '$ClusterName'..." -ForegroundColor Cyan

$clusterExists = k3d cluster list --no-headers 2>$null | Select-String $ClusterName
if ($clusterExists) {
    Write-Host "[OK] Cluster '$ClusterName' already exists - skipping creation" -ForegroundColor Green
} else {
    # --no-deploy traefik: disable k3s built-in Traefik ingress controller.
    # We install NGINX Ingress Controller instead via ArgoCD (wave -1) because:
    #   - NGINX is the industry standard (80%+ of production clusters use it)
    #   - Better annotation support, CORS, timeouts, proxy tuning
    #   - More familiar to engineers coming from traditional NGINX setups
    k3d cluster create $ClusterName `
        --port "80:80@loadbalancer" `
        --port "443:443@loadbalancer" `
        --agents 2 `
        --k3s-arg "--disable=traefik@server:0" `
        --wait
    Write-Host "[OK] Cluster created (Traefik disabled - NGINX will be installed by ArgoCD)" -ForegroundColor Green
}

kubectl cluster-info

# -- Step 3: Configure Windows hosts file -------------------------------------

Write-Host "`n[3/7] Configuring Windows hosts file..." -ForegroundColor Cyan

$hostsFile  = "C:\Windows\System32\drivers\etc\hosts"
$hostEntries = @(
    "127.0.0.1   identity.local",
    "127.0.0.1   workspace.local",
    "127.0.0.1   argocd.local",
    "127.0.0.1   grafana.local",
    "127.0.0.1   prometheus.local",
    "127.0.0.1   alertmanager.local"
)

$hostsContent = Get-Content $hostsFile -Raw
foreach ($entry in $hostEntries) {
    $hostname = $entry.Split(" ")[-1]
    if ($hostsContent -notmatch [regex]::Escape($hostname)) {
        try {
            Add-Content -Path $hostsFile -Value $entry
            Write-Host "  Added: $entry" -ForegroundColor Gray
        } catch {
            Write-Warning "  Could not write to hosts file. Please manually add: $entry (Run text editor as Admin)"
        }
    } else {
        Write-Host "  [OK] Already exists: $hostname" -ForegroundColor Green
    }
}

# -- Step 4: Install ArgoCD ----------------------------------------------------

Write-Host "`n[4/7] Installing ArgoCD..." -ForegroundColor Cyan

kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

Write-Host "Waiting for ArgoCD server to be ready (may take 2-3 minutes)..."
kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=180s

Write-Host "[OK] ArgoCD installed" -ForegroundColor Green

# -- Step 5: Get ArgoCD initial password ---------------------------------------

Write-Host "`n[5/7] Retrieving ArgoCD admin password..." -ForegroundColor Cyan

$argoPwd = kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | `
    ForEach-Object { [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($_)) }

Write-Host ""
Write-Host "  ArgoCD URL:      https://argocd.local  (after bootstrap)" -ForegroundColor White
Write-Host "  ArgoCD User:     admin" -ForegroundColor White
Write-Host "  ArgoCD Password: $argoPwd" -ForegroundColor Yellow
Write-Host "  (Save this password!)" -ForegroundColor Yellow

# Port-forward ArgoCD temporarily to bootstrap
Start-Process powershell -ArgumentList "kubectl port-forward svc/argocd-server -n argocd 9090:443" -WindowStyle Minimized
Start-Sleep -Seconds 5

# Login via CLI
argocd login localhost:9090 --username admin --password $argoPwd --insecure

# -- Step 6: Add private repo credentials --------------------------------------

Write-Host "`n[6/7] Configuring ArgoCD ? GitHub private repo access..." -ForegroundColor Cyan
Write-Host ""
Write-Host "  Your repo is PRIVATE. We need a GitHub PAT (Personal Access Token)." -ForegroundColor Yellow
Write-Host "  Generate one at: https://github.com/settings/tokens" -ForegroundColor Yellow
Write-Host "  Scopes needed: repo (read access only)" -ForegroundColor Yellow
Write-Host ""

$githubPAT = Read-Host "Enter your GitHub PAT"
argocd repo add $GithubRepo --username chikuu29 --password $githubPAT --upsert

# -- Step 7: Bootstrap App-of-Apps --------------------------------------------

Write-Host "`n[7/7] Bootstrapping App-of-Apps in ArgoCD..." -ForegroundColor Cyan

argocd app create app-of-apps `
    --repo $GithubRepo `
    --path infra/gitops/argocd `
    --dest-server https://kubernetes.default.svc `
    --dest-namespace argocd `
    --sync-policy automated `
    --auto-prune `
    --self-heal `
    --upsert

argocd app sync app-of-apps --timeout 60

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host " Bootstrap complete!" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor White
Write-Host "  1. Build + push Docker images:" -ForegroundColor White
Write-Host "     docker build -t cchiku1999/saas-identity-backend:latest ./apps/identity_server/backend" -ForegroundColor Gray
Write-Host "     docker push cchiku1999/saas-identity-backend:latest" -ForegroundColor Gray
Write-Host "     (repeat for identity-web, workspace-backend, workspace-web)" -ForegroundColor Gray
Write-Host ""
Write-Host "  2. Seal your secrets with kubeseal (see sealed-secret.yaml files)" -ForegroundColor White
Write-Host ""
Write-Host "  3. Open ArgoCD UI:     https://argocd.local" -ForegroundColor White
Write-Host "  4. Open Grafana:       https://grafana.local  (after monitoring sync)" -ForegroundColor White
Write-Host "  5. Open Identity app:  https://identity.local" -ForegroundColor White
Write-Host "  6. Open Workspace app: https://workspace.local" -ForegroundColor White

