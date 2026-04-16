# GitOps Production Deployment Guide
## SaaS Platform — Kubernetes + ArgoCD + Grafana

> **What this is**: A complete, production-style local Kubernetes deployment of the SaaS multi-tenant platform using GitOps principles — where your Git repository is the single source of truth for everything running in the cluster.

---

## Table of Contents

1. [What is GitOps?](#1-what-is-gitops)
2. [Full Architecture](#2-full-architecture)
3. [Every Tool Explained](#3-every-tool-explained)
4. [Complete File Reference](#4-complete-file-reference)
5. [Step-by-Step Installation Guide](#5-step-by-step-installation-guide)
6. [Bootstrap the Cluster](#6-bootstrap-the-cluster)
7. [Build and Push Docker Images](#7-build-and-push-docker-images)
8. [Seal Your Secrets](#8-seal-your-secrets)
9. [Accessing All Services](#9-accessing-all-services)
10. [How ArgoCD Works Day-to-Day](#10-how-argocd-works-day-to-day)
11. [How Grafana Monitoring Works](#11-how-grafana-monitoring-works)
12. [Deploying a Code Change (GitOps Flow)](#12-deploying-a-code-change-gitops-flow)
13. [Troubleshooting](#13-troubleshooting) 

---

## 1. What is GitOps?

**GitOps** is a deployment strategy where:

- Your **Git repository** is the single source of truth for what runs in Kubernetes
- You **never run `kubectl apply` manually** in production
- A tool (ArgoCD) **watches your repo** and automatically applies changes
- If someone manually changes something in Kubernetes, ArgoCD **reverts it back** to match Git

```
Developer pushes code → GitHub Actions builds Docker image
                      → Updates image tag in infra/gitops/
                      → ArgoCD detects change (polls every 3 min)
                      → ArgoCD applies the new Deployment
                      → Kubernetes performs rolling update
                      → Zero downtime deploy ✓
```

**Why GitOps?**
- Every change has a Git history — full audit trail
- Roll back any deploy with `git revert`
- No manual `kubectl` commands needed
- Developers don't need direct cluster access
- Disaster recovery: rebuild entire cluster from Git in minutes

---

## 2. Full Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Your Windows Machine                      │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐  │
│  │                Docker Desktop                         │  │
│  │                                                       │  │
│  │  ┌─────────────────────────────────────────────────┐ │  │
│  │  │          k3d (k3s Kubernetes Cluster)            │ │  │
│  │  │                                                  │ │  │
│  │  │  ┌──────────┐  ┌───────────┐  ┌─────────────┐  │ │  │
│  │  │  │ identity │  │ workspace │  │  monitoring  │  │ │  │
│  │  │  │namespace │  │ namespace │  │  namespace   │  │ │  │
│  │  │  │          │  │           │  │              │  │ │  │
│  │  │  │ FastAPI  │  │  FastAPI  │  │  Prometheus  │  │ │  │
│  │  │  │ React    │  │  React    │  │  Grafana     │  │ │  │
│  │  │  │ Postgres │  │  MongoDB  │  │  Loki        │  │ │  │
│  │  │  │ Redis    │  │           │  │  Alertmgr    │  │ │  │
│  │  │  └──────────┘  └───────────┘  └─────────────┘  │ │  │
│  │  │                                                  │ │  │
│  │  │  ┌───────────┐  ┌────────────────────────────┐  │ │  │
│  │  │  │  argocd   │  │       kube-system           │  │ │  │
│  │  │  │ namespace │  │  Traefik Ingress Controller │  │ │  │
│  │  │  │           │  │  Sealed Secrets Controller  │  │ │  │
│  │  │  │  ArgoCD   │  │                            │  │ │  │
│  │  │  │  Web UI   │  └────────────────────────────┘  │ │  │
│  │  │  └───────────┘                                   │ │  │
│  │  └─────────────────────────────────────────────────┘ │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                             │
│  Browser URLs:                                              │
│  http://identity.local    → Identity Server (React)         │
│  http://identity.local/api → Identity FastAPI               │
│  http://workspace.local   → Workspace (React)               │
│  http://workspace.local/api → Workspace FastAPI             │
│  http://argocd.local      → ArgoCD Web UI                   │
│  http://grafana.local     → Grafana Dashboards              │
│  http://prometheus.local  → Prometheus                      │
│  http://alertmanager.local → Alertmanager                   │
└─────────────────────────────────────────────────────────────┘
```

---

## 3. Every Tool Explained

### 🐳 Docker Desktop
**What it is**: Runs Docker on Windows, which is required by k3d.
**Why we need it**: k3d creates Kubernetes nodes as Docker containers.
**Install**: https://www.docker.com/products/docker-desktop/

---

### ☸️ k3d (runs k3s Kubernetes)
**What it is**: A tool that creates a full Kubernetes cluster inside Docker containers.
**Why k3d over full Kubernetes?**
- Full Kubernetes (kubeadm) is hard to set up on Windows and uses 4+ GB RAM
- k3d creates a production-identical cluster in **30 seconds** using only ~500MB RAM
- Uses k3s internally — the same Kubernetes but optimized and lightweight
- Comes with **Traefik Ingress** pre-installed — no extra setup needed

**What is k3s?** Lightweight Kubernetes certified by the CNCF. Used in production at many companies. 100% compatible with standard Kubernetes manifests.

---

### 🔄 ArgoCD (GitOps Operator)
**What it is**: A Kubernetes controller that watches your Git repository and keeps the cluster in sync with what's defined in Git.
**Why ArgoCD?**
- **Web UI**: Visual dashboard showing sync status of every service
- **Auto-sync**: Detects changes in Git and applies them automatically
- **Self-heal**: If someone manually changes Kubernetes, ArgoCD reverts it
- **App-of-Apps**: One root app manages all other apps — very organized
- **Rollback**: Click a button in the UI to roll back to any previous Git commit

**Ports/URL**: `http://argocd.local` (after setup)

---

### 🐳 Docker Hub (Registry)
**What it is**: Public/private image registry to store your built container images.
**Why Docker Hub?** Free, widely used, no infrastructure to maintain.
**Alternative**: You could use GitHub Container Registry (GHCR) — same concept.

Your 4 images:
- `docker.io/cchiku1999/saas-identity-backend`
- `docker.io/cchiku1999/saas-identity-web`
- `docker.io/cchiku1999/saas-workspace-backend`
- `docker.io/cchiku1999/saas-workspace-web`

---

### 🔐 Sealed Secrets
**What it is**: A Kubernetes controller that lets you store **encrypted** secrets safely in Git.
**The problem it solves**: Normal Kubernetes Secrets are just base64 encoded — NOT encrypted. You can't commit them to Git. Sealed Secrets encrypts them with a key that only lives in your cluster.
**How it works**:
1. You create a normal secret → encrypt it with `kubeseal` → get a `SealedSecret` YAML
2. This encrypted YAML is safe to commit to Git
3. Only the Sealed Secrets controller in your cluster can decrypt it
4. ArgoCD applies the `SealedSecret` → controller creates the real `Secret`

---

### 🔀 NGINX Ingress Controller
**What it is**: The industry-standard reverse proxy and load balancer for Kubernetes. Routes external HTTP traffic from `*.local` hostnames to internal Kubernetes Services.
**Why NGINX over Traefik?**
- Used in 80%+ of production Kubernetes deployments
- Familiar to every developer who has used NGINX before
- Rich annotation system: CORS, timeouts, body size, caching, real IP forwarding
- More battle-tested and better community support
- Standard `networking.k8s.io/v1` Ingress API — no vendor-specific CRDs

**How it's installed**: Via Helm, managed by ArgoCD at sync wave `-1` (before any Ingress resources).
**Why sync wave -1?** Ingress resources in identity/workspace namespaces must have a working controller to attach to — if NGINX isn't running, those Ingress objects sit with "no controller found" errors.

**Namespace**: `ingress-nginx`
**Key annotations used**:
```yaml
nginx.ingress.kubernetes.io/proxy-read-timeout: "120"  # FastAPI timeout
nginx.ingress.kubernetes.io/proxy-body-size: "50m"     # File uploads
nginx.ingress.kubernetes.io/enable-cors: "true"        # CORS headers
nginx.ingress.kubernetes.io/proxy-buffer-size: "16k"   # Large JWT tokens
```

---

### 📊 Prometheus
**What it is**: Time-series metrics database. Scrapes `/metrics` endpoints from your pods every 15 seconds.
**What it collects**: HTTP request count, latency, error rates, CPU, memory, disk — everything.
**URL**: `http://prometheus.local`

---

### 📈 Grafana
**What it is**: Dashboard tool that visualizes Prometheus metrics and Loki logs.
**What you get**: 3 pre-built dashboards for Platform Overview, Identity Server, and Workspace.
**URL**: `http://grafana.local` (admin / your-password)

---

### 📋 Loki + Promtail
**What it is**: Log aggregation system. Promtail is a DaemonSet that runs on every Kubernetes node and ships pod logs to Loki. Grafana reads logs from Loki.
**Why Loki?** Much cheaper than Elasticsearch. Indexes only metadata (labels), not log content. View logs in Grafana's Explore tab.

---

### 🚨 Alertmanager
**What it is**: Receives alerts from Prometheus and routes them to Gmail SMTP.
**Alert rules configured**: High error rate, high latency, pod crash-looping, PVC full, high memory.
**URL**: `http://alertmanager.local`

---

### 📦 HPA (Horizontal Pod Autoscaler)
**What it is**: Built into Kubernetes. Automatically adds/removes pod replicas based on CPU/memory.
**Our config**: identity-backend and workspace-backend scale from **2 → 5 replicas** when CPU > 70%.

---

### ⚙️ GitHub Actions (CI/CD)
**What it is**: Automation that runs when you `git push`. Builds Docker images and pushes them to Docker Hub, then commits the new image tag back to the GitOps manifests.
**Result**: ArgoCD sees the tag change → automatically deploys the new version → zero-downtime rolling update.

---

## 4. Complete File Reference

Every file in `infra/gitops/` explained:

```
infra/gitops/
│
├── bootstrap-local.ps1
├── argocd/
│   ├── app-of-apps.yaml
│   ├── app-infra.yaml
│   ├── app-identity.yaml
│   ├── app-workspace.yaml
│   └── app-monitoring.yaml
│
├── infra/
│   ├── kustomization.yaml
│   ├── sealed-secrets-controller.yaml
│   ├── identity-postgres/
│   │   ├── kustomization.yaml
│   │   ├── namespace.yaml
│   │   ├── pvc.yaml
│   │   ├── sealed-secret.yaml
│   │   ├── statefulset.yaml
│   │   └── service.yaml
│   ├── identity-redis/
│   │   ├── kustomization.yaml
│   │   ├── pvc.yaml
│   │   ├── statefulset.yaml
│   │   └── service.yaml
│   └── workspace-mongodb/
│       ├── kustomization.yaml
│       ├── namespace.yaml
│       ├── pvc.yaml
│       ├── sealed-secret.yaml
│       ├── configmap-init.yaml
│       ├── statefulset.yaml
│       └── service.yaml
│
├── apps/
│   ├── identity/
│   │   ├── kustomization.yaml
│   │   ├── namespace.yaml
│   │   ├── configmap.yaml
│   │   ├── identity-backend-deployment.yaml
│   │   ├── identity-backend-service.yaml
│   │   ├── identity-backend-hpa.yaml
│   │   ├── identity-web-deployment.yaml
│   │   ├── identity-web-service.yaml
│   │   └── ingress.yaml
│   └── workspace/
│       ├── kustomization.yaml
│       ├── namespace.yaml
│       ├── configmap.yaml
│       ├── workspace-backend-deployment.yaml
│       ├── workspace-backend-service.yaml
│       ├── workspace-backend-hpa.yaml
│       ├── workspace-web-deployment.yaml
│       ├── workspace-web-service.yaml
│       └── ingress.yaml
│
└── monitoring/
    ├── kustomization.yaml
    ├── namespace.yaml
    ├── kube-prometheus-stack/
    │   ├── helmchart.yaml
    │   └── values.yaml
    ├── loki-stack/
    │   └── helmchart.yaml
    ├── dashboards/
    │   └── platform-overview.yaml
    └── alerting/
        ├── prometheus-rules.yaml
        └── alertmanager-config.yaml
```

---

### 📄 `bootstrap-local.ps1`
**What**: One-shot PowerShell script to set up the entire local cluster from scratch.
**Does**: Installs CLI tools → creates k3d cluster → patches Windows hosts file → installs ArgoCD → asks for GitHub PAT → bootstraps App-of-Apps.
**Run**: `.\infra\gitops\bootstrap-local.ps1` (as Administrator)

---

### 📄 `argocd/app-of-apps.yaml`
**What**: The root ArgoCD Application. This is the only thing you manually create in ArgoCD. It watches `infra/gitops/argocd/` and creates all the child Applications from there.
**Why App-of-Apps pattern?** Instead of manually registering each service in ArgoCD, one root app manages all others. Add a new service → add one YAML file → ArgoCD picks it up automatically.

---

### 📄 `argocd/app-infra.yaml`
**What**: ArgoCD Application that watches `infra/gitops/infra/` and deploys all databases (PostgreSQL, Redis, MongoDB) and the Sealed Secrets controller.
**Sync Wave**: `0` — runs **before** apps start, because apps need databases to be ready.

---

### 📄 `argocd/app-identity.yaml`
**What**: ArgoCD Application that watches `infra/gitops/apps/identity/` and deploys identity-backend + identity-web Deployments.
**Sync Wave**: `1` — runs after infra (wave 0).

---

### 📄 `argocd/app-workspace.yaml`
**What**: ArgoCD Application that watches `infra/gitops/apps/workspace/` and deploys workspace-backend + workspace-web Deployments.
**Sync Wave**: `1` — same wave as identity (they don't depend on each other).

---

### 📄 `argocd/app-monitoring.yaml`
**What**: ArgoCD Application that watches `infra/gitops/monitoring/` and deploys the entire observability stack via Helm.
**Sync Wave**: `2` — runs after apps are deployed so Prometheus can start scraping them immediately.

### 📄 `argocd/nginx-ingress.yaml`
**What**: ArgoCD Application that installs NGINX Ingress Controller via Helm at sync wave `-1`.
**Why wave -1?** NGINX must be running before any `Ingress` resources in identity/workspace namespaces are applied — otherwise those resources have no controller to bind to and OIDC/auth flows would fail.
**Key config**: Runs as DaemonSet with `hostNetwork: true` so it can bind directly to host ports 80/443 via the k3d port mapping. Prometheus metrics enabled for scraping.

---

### 📄 `infra/kustomization.yaml`
**What**: Kustomize aggregator — lists all resources in the `infra/` folder so ArgoCD knows what to apply. Applies Sealed Secrets controller first (it must exist before `SealedSecret` resources are decrypted).
**Kustomize** is a Kubernetes-native way to manage YAML without Helm. No templating — just plain YAML with overlays and patches.

---

### 📄 `infra/sealed-secrets-controller.yaml`
**What**: Installs the Sealed Secrets controller as a nested ArgoCD Application at sync wave `-1` (before everything). Without this running, no `SealedSecret` in the cluster can be decrypted.

---

### 📄 `infra/identity-postgres/statefulset.yaml`
**What**: Kubernetes StatefulSet for PostgreSQL 15.
**Why StatefulSet not Deployment?** StatefulSets give pods a stable network identity and guarantee ordered startup/shutdown — critical for databases that need stable hostnames and ordered initialization.
**Probes**: Uses `pg_isready` command to check PostgreSQL health.
**Storage**: Mounts a PVC at `/var/lib/postgresql/data`.

---

### 📄 `infra/identity-postgres/pvc.yaml`
**What**: PersistentVolumeClaim — requests 5GB of storage from Kubernetes.
**StorageClass**: `local-path` — k3s's built-in provisioner that creates a directory on the host filesystem. Data survives pod restarts.
**Why PVC?** Without a PVC, database data lives inside the container and is deleted when the pod restarts.

---

### 📄 `infra/identity-postgres/sealed-secret.yaml`
**What**: Encrypted Kubernetes Secret containing PostgreSQL credentials (`POSTGRES_USER`, `POSTGRES_PASSWORD`, `DATABASE_URL`).
**Status**: Placeholder — you must run `kubeseal` to fill in real values before deploying.
**See**: [Section 8 — Seal Your Secrets](#8-seal-your-secrets)

---

### 📄 `infra/identity-redis/statefulset.yaml`
**What**: Redis 7 StatefulSet with RDB persistence enabled (saves to disk every 60 seconds).
**Why Redis?** Identity backend uses Redis for: login sessions, auth codes, OTP cache, permission cache, rate limiting.

---

### 📄 `infra/workspace-mongodb/statefulset.yaml`
**What**: MongoDB 7 StatefulSet. Mounts the init script from a ConfigMap.
**Why MongoDB?** Workspace uses MongoDB for flexible schema storage: UI templates, org-scoped records, app configs.

---

### 📄 `infra/workspace-mongodb/configmap-init.yaml`
**What**: Kubernetes ConfigMap containing the MongoDB init script (`init-mongo.js`). Mounted into the pod at `/docker-entrypoint-initdb.d/` — MongoDB runs this automatically on first start to create the `workspace_db` database.

---

### 📄 `apps/identity/identity-backend-deployment.yaml`
**What**: Kubernetes Deployment for the Identity Server FastAPI backend.
**Key details**:
- `ingressClassName: nginx` — routes through NGINX Ingress (not Traefik)
- Routes `/api`, `/.well-known`, `/health`, `/metrics` → identity-backend:8000
- Routes `/` → identity-web:80 (React SPA catch-all)
- CORS enabled at NGINX level as a safety net alongside FastAPI CORS middleware
- Real client IP forwarded for rate limiting in identity-backend
- Static asset caching (JS/CSS/images expire in 1 day)

---

### 📄 `apps/identity/configmap.yaml`
**What**: Non-sensitive environment variables for identity-backend (ENV, DOMAIN_NAME, CORS_ORIGINS, token lifetimes, SMTP settings). Safe to commit to Git because there are no secrets here.
**Secrets** (DATABASE_URL, REDIS_URL, JWT keys, SMTP password) come from the `SealedSecret` — injected separately via `envFrom.secretRef`.

---

### 📄 `apps/identity/identity-backend-hpa.yaml`
**What**: HorizontalPodAutoscaler — automatically scales identity-backend pods.
**Rules**:
- Minimum: 2 pods always running
- Maximum: 5 pods
- Scale up when: average CPU > 70% OR average memory > 80%
- Scale-down delay: 5 minutes (prevents flapping — don't immediately remove pods after a short load spike)
- Scale-up delay: 60 seconds

---

### 📄 `apps/identity/ingress.yaml`
**What**: NGINX Ingress resource telling NGINX how to route traffic for `identity.local`.
**Routing rules**:
- `identity.local/api` → identity-backend Service (port 8000)
- `identity.local/.well-known` → identity-backend (OIDC discovery endpoints)
- `identity.local/health` → identity-backend (Kubernetes probe paths)
- `identity.local/metrics` → identity-backend (Prometheus scrape path)
- `identity.local/` → identity-web Service (port 80) — React SPA catch-all

### 📄 `apps/workspace/ingress.yaml`
**What**: NGINX Ingress for `workspace.local` with an extra `/public` path for FastAPI's static file storage mount.
**Routing rules**:
- `workspace.local/api` → workspace-backend (FastAPI)
- `workspace.local/public` → workspace-backend (FastAPI StaticFiles — file upload storage)
- `workspace.local/health` → workspace-backend
- `workspace.local/metrics` → workspace-backend
- `workspace.local/` → workspace-web (React SPA)
**Extra**: `proxy-body-size: 50m` allows file uploads up to 50MB.

---

### 📄 `monitoring/kube-prometheus-stack/helmchart.yaml`
**What**: ArgoCD Application that deploys the `kube-prometheus-stack` Helm chart. This single chart installs Prometheus + Grafana + Alertmanager + kube-state-metrics + node-exporter in one shot.
**Why Helm here?** The Prometheus stack is complex with dozens of sub-charts — Helm is the standard distribution format for it.

---

### 📄 `monitoring/kube-prometheus-stack/values.yaml`
**What**: Configuration for the Prometheus stack Helm chart.
**Key config**:
- Grafana: enabled with Ingress at `grafana.local`, dashboard sidecar enabled (reads ConfigMaps with `grafana_dashboard: "1"` label)
- Prometheus: 15-day retention, 10GB storage, annotation-based auto-discovery for FastAPI pods
- Alertmanager: enabled with `alertmanager.local` ingress
- Node Exporter + kube-state-metrics: enabled for cluster-level metrics

---

### 📄 `monitoring/loki-stack/helmchart.yaml`
**What**: Deploys Loki (log storage) + Promtail (log shipper DaemonSet). Promtail runs on every Kubernetes node and ships all pod stdout/stderr to Loki. Grafana reads Loki via the pre-configured Loki datasource.

---

### 📄 `monitoring/dashboards/platform-overview.yaml`
**What**: Grafana dashboard JSON embedded in a Kubernetes ConfigMap, labelled `grafana_dashboard: "1"`. The Grafana sidecar automatically detects this ConfigMap and loads the dashboard — no manual import needed.
**Shows**: Request rates, error rates, pod counts, p99 latency for both services side-by-side.

---

### 📄 `monitoring/alerting/prometheus-rules.yaml`
**What**: `PrometheusRule` CRD — Prometheus loads these alert rules and evaluates them every 30 seconds.
**Alerts configured**:

| Alert | Condition |
|---|---|
| `IdentityBackendHighErrorRate` | 5xx rate > 1% for 5 minutes |
| `WorkspaceBackendHighErrorRate` | 5xx rate > 1% for 5 minutes |
| `IdentityBackendHighLatency` | p99 > 2 seconds for 5 minutes |
| `WorkspaceBackendHighLatency` | p99 > 2 seconds for 5 minutes |
| `PodCrashLooping` | Pod restarted > 3 times in 10 minutes |
| `PodNotReady` | Pod not in Ready state for > 5 minutes |
| `PVCHighUsage` | PVC storage > 80% full |
| `HighMemoryUsage` | Container memory > 90% of limit for 10 minutes |

---

### 📄 `monitoring/alerting/alertmanager-config.yaml`
**What**: Alertmanager routing configuration embedded in a Kubernetes Secret. Routes alerts to your Gmail account.
**Alert routing**:
- `critical` alerts → immediate email (10s group wait), repeats every 1 hour
- `warning` alerts → standard email (30s group wait), repeats every 6 hours
- If a pod is down, its latency/error alerts are suppressed (pod down = root cause known)

> ⚠️ **IMPORTANT**: You must replace `YOUR_GMAIL@gmail.com` and `YOUR_GMAIL_APP_PASSWORD` with real values before sealing this secret.

---

### 📄 `.github/workflows/build-identity.yml`
**What**: GitHub Actions CI workflow that runs on every push to `apps/identity_server/**`.
**Steps**:
1. Build `saas-identity-backend` Docker image → push to Docker Hub with `git-sha` tag
2. Build `saas-identity-web` Docker image → push to Docker Hub with `git-sha` tag
3. Update image tags in `infra/gitops/apps/identity/*.yaml`
4. Commit and push → ArgoCD detects the change → rolling deploy

---

### 📄 `.github/workflows/build-workspace.yml`
**What**: Same as `build-identity.yml` but for `apps/work_space/**`.

---

## 5. Step-by-Step Installation Guide

### Prerequisites Check

Before starting, make sure you have:
- Windows 10/11 (64-bit)
- At least **8 GB RAM** free
- Docker Desktop installed and running
- A GitHub account with this repo
- A Docker Hub account (`cchiku1999`)

---

### Install All Required CLI Tools

Open **PowerShell as Administrator** and run each of these:

```powershell
# 1️⃣ Install k3d (Kubernetes in Docker)
winget install --id k3d-io.k3d -e

# 2️⃣ Install kubectl (Kubernetes CLI)
winget install --id Kubernetes.kubectl -e

# 3️⃣ Install Helm (Kubernetes package manager)
winget install --id Helm.Helm -e

# 4️⃣ Install ArgoCD CLI
winget install --id argoproj.argocd -e

# Verify all tools installed correctly
k3d version
kubectl version --client
helm version
argocd version --client
```

**Install kubeseal (for Sealed Secrets):**
```powershell
# Download the latest kubeseal.exe from GitHub releases
$version = "0.27.1"
$url = "https://github.com/bitnami-labs/sealed-secrets/releases/download/v$version/kubeseal-$version-windows-amd64.tar.gz"
Invoke-WebRequest -Uri $url -OutFile "kubeseal.tar.gz"

# Extract and move to a folder in your PATH
tar -xzf kubeseal.tar.gz kubeseal.exe
Move-Item kubeseal.exe "C:\Windows\System32\kubeseal.exe"

# Verify
kubeseal --version
```

**Docker Hub login:**
```powershell
docker login
# Enter your Docker Hub username: cchiku1999
# Enter your Docker Hub password or access token
```

**GitHub Secrets setup** (needed for GitHub Actions):
1. Go to your GitHub repo → Settings → Secrets and variables → Actions
2. Click "New repository secret"
3. Name: `DOCKERHUB_TOKEN`
4. Value: Your Docker Hub access token (from https://hub.docker.com/settings/security)
5. Click "Add secret"

---

## 6. Bootstrap the Cluster

### Option A: Use the Bootstrap Script (Recommended)

```powershell
# Navigate to your project root
cd D:\Development\saas_platform

# Allow script execution for this session
Set-ExecutionPolicy Bypass -Scope Process

# Run bootstrap (as Administrator)
.\infra\gitops\bootstrap-local.ps1
```

The script will:
1. Install missing CLI tools automatically
2. Create the k3d cluster `saas-local` with ports 80 and 443 mapped
3. Add all `*.local` entries to your Windows hosts file
4. Install ArgoCD into the cluster
5. Ask for your GitHub Personal Access Token (PAT) to access the private repo
6. Bootstrap the App-of-Apps — ArgoCD will take over from here

---

### Option B: Manual Step-by-Step

If you prefer to run each command manually:

### Step 1 — Create the k3d cluster (Traefik disabled):
```powershell
# --k3s-arg "--disable=traefik@server:0" disables the built-in Traefik.
# ArgoCD will install NGINX Ingress Controller (wave -1) instead.
k3d cluster create saas-local `
  --port "80:80@loadbalancer" `
  --port "443:443@loadbalancer" `
  --agents 2 `
  --k3s-arg "--disable=traefik@server:0" `
  --wait

# Verify the cluster is running
kubectl get nodes
# Expected: 3 nodes (1 server + 2 agents), all STATUS=Ready

# Confirm Traefik is NOT running (should return empty)
kubectl get pods -n kube-system | Select-String traefik
```

**Step 2 — Update Windows hosts file (run as Administrator):**
```powershell
$hostsFile = "C:\Windows\System32\drivers\etc\hosts"
$entries = @(
    "127.0.0.1   identity.local",
    "127.0.0.1   workspace.local",
    "127.0.0.1   argocd.local",
    "127.0.0.1   grafana.local",
    "127.0.0.1   prometheus.local",
    "127.0.0.1   alertmanager.local"
)
$entries | ForEach-Object { Add-Content $hostsFile $_ }
```

**Step 3 — Install ArgoCD:**
```powershell
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for ArgoCD to be ready (takes 2-3 minutes)
kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=180s
```

**Step 4 — Get ArgoCD admin password:**
```powershell
# Get the initial admin password
$pwd = kubectl -n argocd get secret argocd-initial-admin-secret `
  -o jsonpath="{.data.password}" |
  ForEach-Object { [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($_)) }
Write-Host "ArgoCD Password: $pwd"
```

**Step 5 — Port-forward ArgoCD temporarily:**
```powershell
# Open a new PowerShell window and run:
kubectl port-forward svc/argocd-server -n argocd 9090:443

# In original window — login to ArgoCD CLI
argocd login localhost:9090 --username admin --password <YOUR_PASSWORD> --insecure
```

**Step 6 — Add your private GitHub repo to ArgoCD:**
```powershell
# Generate a GitHub PAT at: https://github.com/settings/tokens
# Scopes needed: repo (Full control of private repositories)

argocd repo add https://github.com/cchiku1999/saas_platform.git `
  --username cchiku1999 `
  --password <YOUR_GITHUB_PAT>
```

**Step 7 — Create the App-of-Apps:**
```powershell
argocd app create app-of-apps `
  --repo https://github.com/cchiku1999/saas_platform.git `
  --path infra/gitops/argocd `
  --dest-server https://kubernetes.default.svc `
  --dest-namespace argocd `
  --sync-policy automated `
  --auto-prune `
  --self-heal

# ArgoCD will now auto-create all child apps and sync everything
argocd app sync app-of-apps
```

---

## 7. Build and Push Docker Images

Before ArgoCD can deploy your services, the Docker images must exist on Docker Hub.

```powershell
# 🔵 Identity Backend (FastAPI)
docker build -t cchiku1999/saas-identity-backend:latest `
  .\apps\identity_server\backend
docker push cchiku1999/saas-identity-backend:latest

# 🔵 Identity Web (React/Nginx)
docker build -t cchiku1999/saas-identity-web:latest `
  .\apps\identity_server\web
docker push cchiku1999/saas-identity-web:latest

# 🟢 Workspace Backend (FastAPI)
docker build -t cchiku1999/saas-workspace-backend:latest `
  .\apps\work_space\backend
docker push cchiku1999/saas-workspace-backend:latest

# 🟢 Workspace Web (React/Nginx)
docker build -t cchiku1999/saas-workspace-web:latest `
  .\apps\work_space\web
docker push cchiku1999/saas-workspace-web:latest
```

After this, ArgoCD will detect that the images exist and complete the deployment.

---

## 8. Seal Your Secrets

Sealed Secrets encrypt your credentials before committing to Git.

**Step 1 — Wait for Sealed Secrets controller to be running:**
```powershell
kubectl get pods -n kube-system | Select-String "sealed-secrets"
# Should show: sealed-secrets-controller-xxx   Running
```

**Step 2 — Create and seal PostgreSQL credentials:**
```powershell
# Create a plain secret (DO NOT COMMIT THIS FILE)
kubectl create secret generic identity-postgres-secret `
  --namespace identity `
  --from-literal=POSTGRES_USER=postgres `
  --from-literal=POSTGRES_PASSWORD=MyStrongPassword123! `
  --from-literal=DATABASE_URL="postgresql+asyncpg://postgres:MyStrongPassword123!@identity-postgres:5432/identity_provider_database" `
  --dry-run=client -o yaml > temp-postgres-secret.yaml

# Seal it
kubeseal --controller-name=sealed-secrets-controller `
  --controller-namespace=kube-system `
  --format yaml < temp-postgres-secret.yaml > `
  .\infra\gitops\infra\identity-postgres\sealed-secret.yaml

# Delete the plain secret (NEVER commit temp-postgres-secret.yaml)
Remove-Item temp-postgres-secret.yaml
```

**Step 3 — Create and seal MongoDB credentials:**
```powershell
kubectl create secret generic workspace-mongodb-secret `
  --namespace workspace `
  --from-literal=MONGO_INITDB_ROOT_USERNAME=workspace_admin `
  --from-literal=MONGO_INITDB_ROOT_PASSWORD=MongoPassword123! `
  --from-literal=MONGO_URI="mongodb://workspace_admin:MongoPassword123!@workspace-mongodb:27017/workspace_db?authSource=admin" `
  --dry-run=client -o yaml > temp-mongo-secret.yaml

kubeseal --controller-name=sealed-secrets-controller `
  --controller-namespace=kube-system `
  --format yaml < temp-mongo-secret.yaml > `
  .\infra\gitops\infra\workspace-mongodb\sealed-secret.yaml

Remove-Item temp-mongo-secret.yaml
```

**Step 4 — Create and seal identity app secrets:**
```powershell
kubectl create secret generic identity-app-secret `
  --namespace identity `
  --from-literal=SECRET_KEY=your-super-secret-key-here `
  --from-literal=LINK_JWT_SECRET=your-link-jwt-secret `
  --from-literal=SMTP_USERNAME=your@gmail.com `
  --from-literal=SMTP_PASSWORD=your-gmail-app-password `
  --dry-run=client -o yaml > temp-identity-app.yaml

kubeseal --controller-name=sealed-secrets-controller `
  --controller-namespace=kube-system `
  --format yaml < temp-identity-app.yaml > `
  .\infra\gitops\infra\identity-app-secret.yaml

Remove-Item temp-identity-app.yaml
```

**Step 5 — Create Docker Hub pull secret:**
```powershell
# Allow Kubernetes to pull from your Docker Hub account
kubectl create secret docker-registry dockerhub-secret `
  --docker-username=cchiku1999 `
  --docker-password=<YOUR_DOCKERHUB_TOKEN> `
  --docker-email=your@email.com `
  --namespace=identity `
  --dry-run=client -o yaml > temp-dockerhub.yaml

kubeseal --controller-name=sealed-secrets-controller `
  --controller-namespace=kube-system `
  --format yaml < temp-dockerhub.yaml > `
  .\infra\gitops\infra\dockerhub-secret-identity.yaml

Remove-Item temp-dockerhub.yaml
# Repeat for workspace namespace
```

**Step 6 — Fix Alertmanager Gmail config:**
```powershell
# Edit the file first: monitoring/alerting/alertmanager-config.yaml
# Replace: YOUR_GMAIL@gmail.com  → your real Gmail
# Replace: YOUR_GMAIL_APP_PASSWORD → real Gmail App Password
# (Generate at: https://myaccount.google.com/apppasswords)

# Then commit and push — ArgoCD applies it
git add infra/gitops/monitoring/alerting/alertmanager-config.yaml
git commit -m "config: add alertmanager gmail credentials"
git push
```

**Step 7 — Commit and push sealed secrets:**
```powershell
git add infra/gitops/infra/
git commit -m "secrets: add sealed secrets for all services"
git push
# ArgoCD detects the change and applies the SealedSecrets → pods restart with credentials
```

---

## 9. Accessing All Services

After successful setup, all services are available via these URLs:

| URL | Service | Credentials |
|---|---|---|
| `http://identity.local` | Identity Server Web (React) | Your app credentials |
| `http://identity.local/api/docs` | Identity FastAPI Swagger UI | — |
| `http://workspace.local` | Workspace Web (React) | Your app credentials |
| `http://workspace.local/api/v1/docs` | Workspace FastAPI Swagger UI | — |
| `http://argocd.local` | ArgoCD Web UI | admin / (initial password) |
| `http://grafana.local` | Grafana Dashboards | admin / (your password) |
| `http://prometheus.local` | Prometheus | — |
| `http://alertmanager.local` | Alertmanager | — |

---

## 10. How ArgoCD Works Day-to-Day

### Opening the ArgoCD UI

1. Open browser → `http://argocd.local`
2. Login: `admin` / (your initial password)
3. You will see all 5 applications:
   - `app-of-apps` → Synced ✓ (green)
   - `app-infra` → Synced ✓ (databases running)
   - `app-identity` → Synced ✓
   - `app-workspace` → Synced ✓
   - `app-monitoring` → Synced ✓

### What each status means

| Status | Meaning |
|---|---|
| **Synced** 🟢 | Kubernetes matches Git exactly |
| **OutOfSync** 🟡 | Git has changes not yet applied |
| **Degraded** 🔴 | Resources failed — click to see why |
| **Progressing** 🔵 | Deployment in progress |

### Rolling back a bad deployment

```powershell
# CLI rollback to previous version
argocd app rollback app-identity

# Or in UI: click app-identity → History → click any previous version → Rollback
```

### Manually triggering a sync

```powershell
argocd app sync app-identity
# Or in UI: click "Sync" button on any app
```

---

## 11. How Grafana Monitoring Works

### Opening Grafana

1. `http://grafana.local`
2. Login: `admin` / (password you sealed in grafana-admin-secret)
3. Navigate → Dashboards → Browse → Find "SaaS Platform — Overview"

### Pre-configured Dashboards

**Platform Overview** (auto-provisioned from ConfigMap):
- Identity Backend request rate (RPS)
- Workspace Backend request rate (RPS)
- 5xx error rates for both services
- Ready pod counts per namespace
- p99 latency time series chart

### Viewing Logs in Grafana

1. Grafana → Explore (compass icon on left)
2. Select data source: **Loki**
3. Type a label filter: `{namespace="identity"}`
4. Click "Run query" → see all pod logs in real time

### Checking Alerts

- Grafana → Alerting → Alert rules — see all active/pending/firing rules
- `http://alertmanager.local` — see currently active alerts and their status

---

## 12. Deploying a Code Change (GitOps Flow)

This is the full zero-downtime deploy flow — everything is automatic after `git push`:

```
1. You edit code in apps/identity_server/backend/
2. git add . && git commit -m "feat: ..." && git push origin main
3. GitHub Actions triggers: build-identity.yml
4. Actions builds Docker image → pushes to Docker Hub with new SHA tag
5. Actions commits new image tag to infra/gitops/apps/identity/identity-backend-deployment.yaml
6. ArgoCD detects the commit (polls every 3 minutes)
7. ArgoCD applies the new Deployment
8. Kubernetes starts new pod with new image
9. New pod passes readiness probe (/health/ready)
10. Kubernetes routes traffic to new pod
11. Old pod is gracefully terminated
12. ArgoCD shows: Synced ✓
```

**Total time from `git push` to live**: approximately 5-8 minutes.

---

## 13. Troubleshooting

### Check pod status

```powershell
# See all pods across all namespaces
kubectl get pods -A

# See pods in specific namespace
kubectl get pods -n identity
kubectl get pods -n workspace
kubectl get pods -n monitoring
kubectl get pods -n argocd
```

### View pod logs

```powershell
# See logs for identity-backend
kubectl logs -n identity -l app=identity-backend --tail=100 -f

# See logs for workspace-backend
kubectl logs -n workspace -l app=workspace-backend --tail=100 -f

# See previous container logs (if pod restarted)
kubectl logs -n identity -l app=identity-backend --previous
```

### Describe a pod (shows events, errors, probe failures)

```powershell
kubectl describe pod -n identity -l app=identity-backend
```

### Common Issues

| Issue | Likely Cause | Fix |
|---|---|---|
| Pod in `CrashLoopBackOff` | Bad env var / secret not found | Check `kubectl logs -n <ns> <pod>` + verify SealedSecrets are applied |
| ArgoCD shows OutOfSync forever | Git repo not accessible | Check `argocd repo list` — re-add PAT |
| `identity.local` not resolving | Hosts file not updated | Re-run hosts file update commands in Administrator PowerShell |
| Images pulling fail (`ImagePullBackOff`) | Docker Hub credentials not set | Create & apply dockerhub-secret in the namespace |
| Prometheus not scraping FastAPI | Missing annotations on pod | Check `prometheus.io/scrape: "true"` annotation in deployment YAML |
| Grafana shows "No data" | Prometheus not yet scraping | Give Prometheus 2-3 minutes after deploy, check `prometheus.local/targets` |

### 🚨 Critical Gotchas (Submodules & CI/CD)

Since your apps (`apps/identity_server`, etc.) are **Git Submodules**, you must observe these strict rules to prevent pipeline failures:

#### 1. The "Two-Step Push" Rule
When you edit code inside an app (e.g., Python or React), running `git push` from the root `saas_platform` folder will **NOT** push your changes. You must:
1. `cd` into the submodule folder (`cd apps/identity_server/backend`) and `git push` the code there first.
2. `cd` back out to the root repository (`cd ../../../`), `git add apps/identity_server/backend`, and `git push` to tell the main repository to update its pointer.

#### 2. ArgoCD "Permission Denied" on Submodules
If ArgoCD fails to sync with `git@github.com: Permission denied (publickey)`, it means your `.gitmodules` file is trying to use SSH instead of HTTPS. 
**Fix**: Edit `.gitmodules` and change `git@github.com:User/Repo.git` to `https://github.com/User/Repo.git`.

#### 3. GitHub Actions "Repository not found" during Checkout
Even with `submodules: true`, GitHub Actions will fail to clone submodules if they are **Private Repositories** under your account.
**Fix**: 
1. Create a Personal Access Token (PAT) with `repo` scope.
2. Add it to GitHub Secrets as `GH_PAT`.
3. Update your `.github/workflows/*.yml` checkout step to use it:
```yaml
      - name: Checkout repository
        uses: actions/checkout@v4
        with:
          token: ${{ secrets.GH_PAT }}
          submodules: true
```

### Reset everything and start fresh

```powershell
# ⚠️ This deletes ALL data in the cluster
k3d cluster delete saas-local

# Recreate from scratch
k3d cluster create saas-local `
  --port "80:80@loadbalancer" `
  --port "443:443@loadbalancer" `
  --agents 2 --wait
```

---

## Quick Reference Card

```powershell
# ── Cluster ─────────────────────────────────────────────────
k3d cluster list                      # List clusters
kubectl get nodes                      # Check node health
kubectl get pods -A                    # All pods all namespaces

# ── ArgoCD ──────────────────────────────────────────────────
argocd app list                        # List all ArgoCD apps
argocd app sync app-identity           # Force sync identity app
argocd app rollback app-identity       # Roll back identity app

# ── Logs ────────────────────────────────────────────────────
kubectl logs -n identity   -l app=identity-backend  -f
kubectl logs -n workspace  -l app=workspace-backend -f
kubectl logs -n monitoring -l app.kubernetes.io/name=grafana -f

# ── Scaling ─────────────────────────────────────────────────
kubectl get hpa -A                     # View autoscaler status
kubectl scale deploy identity-backend -n identity --replicas=3

# ── Secrets ─────────────────────────────────────────────────
kubectl get sealedsecrets -A           # List all sealed secrets
kubectl get secrets -n identity        # List decrypted secrets

# ── Destroy ─────────────────────────────────────────────────
k3d cluster delete saas-local          # Delete entire cluster
```
