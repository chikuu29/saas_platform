param(
    [string]$DockerHubUsername = "cchiku1999"
)

$ErrorActionPreference = "Stop"

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host " Building & Pushing SaaS Images" -ForegroundColor Cyan
Write-Host "=========================================`n" -ForegroundColor Cyan

$services = @(
    @{ Name = "saas-identity-backend"; Path = "./apps/identity_server/backend" },
    @{ Name = "saas-identity-web"; Path = "./apps/identity_server/web" },
    @{ Name = "saas-workspace-backend"; Path = "./apps/work_space/backend" },
    @{ Name = "saas-workspace-web"; Path = "./apps/work_space/web" }
)

foreach ($service in $services) {
    $imageTag = "$($DockerHubUsername)/$($service.Name):latest"
    
    Write-Host "--> Building $($service.Name)..." -ForegroundColor Yellow
    docker build -t $imageTag $service.Path
    
    Write-Host "--> Pushing $imageTag to Docker Hub..." -ForegroundColor Yellow
    docker push $imageTag
    Write-Host "[OK] Pushed $($service.Name)`n" -ForegroundColor Green
}

Write-Host "=========================================" -ForegroundColor Green
Write-Host " All images built and pushed successfully!" -ForegroundColor Green
Write-Host " ArgoCD will notice the new `:latest` tags eventually," -ForegroundColor White
Write-Host " but you can force an update by deleting the failing pods so they restart." -ForegroundColor Gray
Write-Host "=========================================" -ForegroundColor Green
