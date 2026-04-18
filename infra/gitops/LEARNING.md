# GitOps Infrastructure — Learning Guide
## Every YAML File Explained: What, Why, and How They Connect

> **Who is this for?** Anyone learning how this SaaS platform is deployed to Kubernetes.
> Read this top-to-bottom. Each section builds on the previous one.

---

## Table of Contents

1. [The Big Picture — What Problem Does All This Solve?](#1-the-big-picture)
2. [The Technology Stack — Every Tool and Why We Use It](#2-the-technology-stack)
3. [How Files Connect — The Dependency Chain](#3-how-files-connect)
4. [The ArgoCD Layer — Your Deployment Brain](#4-the-argocd-layer)
5. [The Infrastructure Layer — Databases and Secrets](#5-the-infrastructure-layer)
6. [The Application Layer — Identity and Workspace](#6-the-application-layer)
7. [The Monitoring Layer — Grafana, Prometheus, Loki](#7-the-monitoring-layer)
8. [Sealed Secrets — Deep Dive](#8-sealed-secrets-deep-dive)
9. [Ingress — How URLs Reach Your Code](#9-ingress-how-urls-reach-your-code)
10. [Kustomization Files — The Glue](#10-kustomization-files-the-glue)
11. [The Sync Wave System — Deployment Order](#11-the-sync-wave-system)
12. [Full File Reference — Every YAML Explained](#12-full-file-reference)
13. [How It All Boots From Zero](#13-how-it-all-boots-from-zero)
14. [Monitoring Deep Dive — Every Component Explained](#14-monitoring-deep-dive--every-component-explained)
15. [kubectl Command Reference — Every Command You Need](#15-kubectl-command-reference)

---

## 1. The Big Picture

### What problem does all this solve?

Without GitOps: you manually run `kubectl apply` commands. If the cluster crashes, you
run them again from memory. If someone changes a setting manually, nobody knows. If two
developers deploy at the same time, things break.

**With GitOps:** Git is the single source of truth. Nobody touches the cluster directly.
ArgoCD constantly watches Git and makes the cluster match it — automatically.

```
Developer pushes code to GitHub
         │
         ▼
GitHub Actions builds Docker image → pushes to Docker Hub
         │
         ▼
GitHub Actions updates image tag in gitops YAML files → pushes to Git
         │
         ▼
ArgoCD detects the Git change
         │
         ▼
ArgoCD applies the new YAML to Kubernetes
         │
         ▼
Kubernetes rolls out new pods (zero downtime)
```

**The golden rule:** If it's not in Git, it doesn't exist in the cluster.

---

## 2. The Technology Stack

| Tool | What It Is | Why We Use It |
|---|---|---|
| **Kubernetes** | Container orchestration | Runs, restarts, scales containers automatically |
| **k3d** | Lightweight Kubernetes on Docker | Runs full Kubernetes on your Windows laptop |
| **ArgoCD** | GitOps controller | Watches Git, deploys to Kubernetes automatically |
| **NGINX Ingress** | Traffic router | Routes `identity.local/api` to the right pod |
| **Sealed Secrets** | Secret encryption | Safely stores passwords in Git |
| **Kustomize** | YAML templating | Combines multiple YAML files without duplication |
| **Helm** | Package manager for Kubernetes | Installs complex apps (Prometheus, Grafana) with one command |
| **Prometheus** | Metrics database | Collects numbers: CPU, request counts, error rates |
| **Grafana** | Dashboard UI | Draws charts from Prometheus data |
| **Loki** | Log aggregation | Collects and stores pod log output |

---

## 3. How Files Connect

### The Full File Tree

```
infra/gitops/
│
├── argocd/                          ← Layer 1: ArgoCD apps (the deployment brain)
│   ├── app-of-apps.yaml             ← ROOT: bootstraps everything
│   ├── app-saas-platform-infra.yaml ← Manages: platform namespaces + databases + secrets
│   ├── app-identity.yaml            ← Manages: identity service
│   ├── app-workspace.yaml           ← Manages: workspace service
│   ├── app-monitoring.yaml          ← Manages: Prometheus + Grafana
│   ├── nginx-ingress.yaml           ← Manages: NGINX traffic router
│   └── argocd-ingress.yaml          ← Makes ArgoCD UI accessible
│
├── platform/                        ← Layer 2: Platform Infrastructure
│   ├── kustomization.yaml           ← Tells kustomize which files to include
│   ├── sealed-secrets-controller.yaml ← The secret decryption engine
│   ├── namespaces/                  ← Common platform namespaces
│   ├── identity-db/                 ← DBs for identity service
│   │   ├── postgres/                ← PostgreSQL StatefulSet & PVC
│   │   └── redis/                   ← Redis StatefulSet & PVC
│   └── workspace-db/                ← MongoDB for workspace service
│
├── apps/                            ← Layer 3: Application services
│   ├── identity/
│   │   ├── kustomization.yaml
│   │   ├── configmap.yaml           ← Non-secret env vars (REDIS_URL, etc.)
│   │   ├── identity-backend-deployment.yaml ← FastAPI pod
│   │   ├── identity-backend-service.yaml    ← Internal routing
│   │   ├── identity-backend-hpa.yaml        ← Auto-scaling
│   │   ├── identity-web-deployment.yaml     ← React frontend pod
│   │   └── ingress.yaml             ← URL routing: identity.local/api → backend
│   └── workspace/
│       └── (same pattern, port 8001)
│
└── monitoring/                      ← Layer 4: Observability
    ├── kustomization.yaml
    ├── namespace.yaml
    ├── kube-prometheus-stack/
    │   ├── helmchart.yaml           ← Installs Prometheus + Grafana via Helm
    │   └── values.yaml              ← Configuration for the Helm chart
    ├── loki-stack/
    │   └── helmchart.yaml           ← Installs Loki + Promtail via Helm
    ├── dashboards/
    │   └── platform-overview.yaml   ← Grafana dashboard definition
    └── alerting/
        ├── prometheus-rules.yaml    ← Alert conditions (e.g., error rate > 1%)
        └── alertmanager-config.yaml ← Where to send alerts (Gmail)
```

---

## 4. The ArgoCD Layer

### What Is ArgoCD?

ArgoCD is a program running inside your Kubernetes cluster. Its job is simple:
1. Watch a Git repository
2. Compare what Git says vs what the cluster has
3. Apply any differences automatically

### `argocd/app-of-apps.yaml` — The Root Application

```
This is the ONLY file you create manually (once).
Everything else is created automatically by ArgoCD.
```

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application        # ArgoCD custom resource (not standard Kubernetes)
metadata:
  name: app-of-apps
  namespace: argocd
spec:
  source:
    path: infra/gitops/argocd    # ← Watch THIS folder in Git
  destination:
    namespace: argocd            # ← Apply what it finds to the argocd namespace
```

**What it does:** Reads every `.yaml` file in `infra/gitops/argocd/` and creates each
one as an ArgoCD Application. This is the "App of Apps" pattern — one app that creates
all other apps.

**Think of it like:** A manager who reads a list and hires workers. The list is Git.
The workers are the other ArgoCD apps.

---

### `argocd/nginx-ingress.yaml` — Traffic Router (Sync Wave -1)

This must deploy **first** (before anything else) because without NGINX running, no
Ingress rules can work.

```yaml
kind: Application
spec:
  source:
    chart: ingress-nginx              # ← Install from Helm repository (not Git)
    repoURL: https://kubernetes.github.io/ingress-nginx
    targetRevision: 4.10.1           # ← Exact version, reproducible
```

**Why NGINX instead of the built-in Traefik?**
- NGINX Ingress is the industry standard
- Better documented, used in production everywhere
- Supports the rewrite annotations we need for URL path stripping

---

### `argocd/app-saas-platform-infra.yaml` — Databases (Sync Wave 0)

Deploys all databases. Must run before apps because apps need databases ready to start.

```yaml
spec:
  source:
    path: infra/gitops/platform          # ← Watches the platform/ folder
```

---

### `argocd/app-identity.yaml` — Identity Service (Sync Wave 1)

```yaml
spec:
  source:
    path: infra/gitops/apps/identity  # ← Watches the identity apps folder
  destination:
    namespace: identity               # ← Deploys into 'identity' namespace
```

---

### `argocd/argocd-ingress.yaml` — Access the ArgoCD Dashboard

Exposes ArgoCD's own UI at `http://argocd.local`:

```
Browser: argocd.local → NGINX Ingress → ArgoCD Server pod
```

---

## 5. The Infrastructure Layer

### Why Databases Are Inside Kubernetes

Your databases run as Kubernetes pods — not in a separate Docker Compose setup.
This means everything is managed in one place (Kubernetes) and can be backed up,
scaled, and monitored the same way as your apps.

---

### `infra/identity-postgres/namespace.yaml` — The Namespace

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: identity
```

**What is a namespace?** A virtual partition inside Kubernetes. Everything belonging
to the identity service lives in the `identity` namespace. This means:
- `kubectl get pods -n identity` shows only identity pods
- Keeps services isolated from each other
- DNS names like `identity-postgres` only resolve inside the same namespace

**Why we need it:** Without a namespace, everything goes into `default` — a mess.

---

### `infra/identity-postgres/pvc.yaml` — Persistent Volume Claim

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: identity-postgres-pvc
spec:
  storageClassName: local-path      # k3s built-in disk provisioner
  resources:
    requests:
      storage: 5Gi                  # Reserve 5GB on the k3d node's disk
```

**What is a PVC?** A request for disk space. The database pod uses this to store data
files so they survive pod restarts.

**Without PVC:** Every time the PostgreSQL pod restarts, ALL data is lost.
**With PVC:** Data lives on the host disk. Pod can restart, data survives.

**Where is the actual data stored?**
Inside the k3d Docker container at:
`/var/lib/rancher/k3s/storage/<pvc-id>/`

---

### `infra/identity-postgres/statefulset.yaml` — The Database Pod

```yaml
apiVersion: apps/v1
kind: StatefulSet                    # Not a Deployment — databases need stable identity
metadata:
  name: identity-postgres
spec:
  containers:
    - name: postgres
      image: postgres:15-alpine     # Official PostgreSQL Docker image
      env:
        - name: PGDATA
          value: /var/lib/postgresql/data/pgdata
      envFrom:
        - secretRef:
            name: identity-postgres-secret  # ← Password from SealedSecret
      volumeMounts:
        - mountPath: /var/lib/postgresql/data  # ← Mount PVC here inside container
```

**StatefulSet vs Deployment:**
- `Deployment` = stateless pods (any pod can die and be replaced)
- `StatefulSet` = stateful pods (each pod has a stable name like `postgres-0`)
- Databases MUST use StatefulSet so they always have a predictable name

---

### `infra/identity-postgres/service.yaml` — Internal DNS

```yaml
apiVersion: v1
kind: Service
metadata:
  name: identity-postgres           # ← This becomes the DNS hostname!
spec:
  selector:
    app: identity-postgres          # ← Route traffic to pods with this label
  ports:
    - port: 5432
```

**This is how other pods find the database.**
The identity-backend doesn't use an IP address. It uses:
```
DATABASE_URL=postgresql://postgres:password@identity-postgres:5432/mydb
                                             ^^^^^^^^^^^^^^^^
                                             This is the Service name — Kubernetes DNS
```

Kubernetes automatically creates a DNS entry `identity-postgres` inside the cluster.

---

## 6. The Application Layer

### `apps/identity/configmap.yaml` — Non-Secret Configuration

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: identity-backend-config
data:
  ENV: "production"
  REDIS_URL: "redis://identity-redis:6379/0"    # ← Internal K8s DNS
  DOMAIN_NAME: "http://identity.local"
  SMTP_SERVER: "smtp.gmail.com"
```

**Rule:** Anything non-sensitive goes in ConfigMap (safe to commit to Git).
Anything sensitive (passwords, keys) goes in SealedSecrets.

**Why REDIS_URL must be here:** The Python code defaults to `localhost:6379`.
In Kubernetes, Redis is NOT on localhost — it's a separate pod accessible as
`identity-redis:6379`. If we don't override it here, the backend crashes.

---

### `apps/identity/identity-backend-deployment.yaml` — The FastAPI App

```yaml
apiVersion: apps/v1
kind: Deployment
spec:
  replicas: 2                       # ← Run 2 copies for redundancy
  strategy:
    type: RollingUpdate             # ← Update one pod at a time (zero downtime)
  template:
    spec:
      containers:
        - name: identity-backend
          image: docker.io/cchiku1999/saas-identity-backend:abc123   # ← From Docker Hub
          envFrom:
            - configMapRef:
                name: identity-backend-config     # ← All ConfigMap vars injected
            - secretRef:
                name: identity-postgres-secret    # ← DB password injected
            - secretRef:
                name: identity-app-secret         # ← SMTP, Razorpay keys injected
          livenessProbe:
            httpGet:
              path: /health/live    # ← Kubernetes checks this every 15s
          readinessProbe:
            httpGet:
              path: /health/ready   # ← Pod only receives traffic when this returns 200
```

**Why two probes?**
- `livenessProbe`: Is the pod alive? If not → restart it
- `readinessProbe`: Is the pod ready for traffic? If not → stop sending requests to it
  (keeps serving traffic to healthy pods while a new one starts up)

**Why `replicas: 2`?** If one pod crashes, the other keeps serving. During updates,
one pod serves while the other updates — zero downtime.

---

### `apps/identity/identity-backend-hpa.yaml` — Auto-Scaling

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
spec:
  scaleTargetRef:
    name: identity-backend
  minReplicas: 2
  maxReplicas: 5
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          averageUtilization: 70    # ← If CPU > 70%, add more pods
```

**What this does:** Automatically adds more identity-backend pods when traffic increases,
and removes them when traffic drops. You pay for what you use.

---

### `apps/identity/ingress.yaml` — URL Routing

This is what makes `http://identity.local/api/auth/login` work:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /$2   # ← Strip /api prefix
spec:
  rules:
    - host: identity.local
      http:
        paths:
          - path: /api(/|$)(.*)             # /api/anything
            backend:
              service:
                name: identity-backend      # → Goes to FastAPI pod
          - path: /                         # Everything else
            backend:
              service:
                name: identity-web          # → Goes to React frontend pod
```

**Request flow:**
```
Browser: GET http://identity.local/api/auth/login
    │
    ▼
NGINX Ingress Controller (reads this Ingress yaml)
    │
    ├── path matches /api/... → rewrite: strip /api → forward to identity-backend:8000
    │   FastAPI receives:  GET /auth/login  ✅
    │
    └── path matches / → forward to identity-web:80
        NGINX in pod serves: React index.html  ✅
```

---

## 7. The Monitoring Layer

### `monitoring/kube-prometheus-stack/helmchart.yaml` — Prometheus + Grafana

This does NOT contain the Grafana/Prometheus YAML directly. Instead it installs them
via Helm — a package manager that handles 100+ complex YAML files for you.

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application                   # ← An ArgoCD child app (app-of-apps pattern)
spec:
  source:
    chart: kube-prometheus-stack    # ← Helm chart name
    repoURL: https://prometheus-community.github.io/helm-charts
    targetRevision: 67.9.0         # ← Exact version
    helm:
      valueFiles:
        - values.yaml               # ← Our custom configuration
```

**What gets installed by this one file:**
- Prometheus (collects metrics)
- Grafana (shows charts at `http://grafana.local`)
- Alertmanager (sends email alerts)
- kube-state-metrics (cluster health metrics)
- node-exporter (CPU, RAM, disk metrics from each node)

---

### `monitoring/kube-prometheus-stack/values.yaml` — Grafana Configuration

This configures the Helm chart. Key settings include:
- Grafana admin password
- Ingress host (`grafana.local`)
- Persistent storage for dashboards
- Which data sources to pre-configure (Prometheus, Loki)

---

### `monitoring/loki-stack/helmchart.yaml` — Log Collection

```yaml
chart: loki-stack
```

**What gets installed:**
- Loki: stores log text from all pods
- Promtail: a DaemonSet (one copy on every node) that reads pod logs and ships to Loki

**How it works:**
```
Pod writes log → Promtail reads it → ships to Loki → Grafana shows it
```
You can then search: "show me all errors from identity-backend in the last 1 hour"

---

### `monitoring/dashboards/platform-overview.yaml` — Grafana Dashboard

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  labels:
    grafana_dashboard: "1"          # ← This magic label tells Grafana to load it!
data:
  platform-overview.json: |
    { "panels": [...] }            # ← Full Grafana dashboard JSON
```

**How Grafana auto-loads it:** Grafana has a sidecar container that watches for
ConfigMaps with the `grafana_dashboard: "1"` label. When it finds one, it
automatically imports the dashboard. No manual clicking in the UI required!

---

### `monitoring/alerting/prometheus-rules.yaml` — Alert Conditions

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule                # ← Custom CRD installed by kube-prometheus-stack
spec:
  groups:
    - name: saas.api.errors
      rules:
        - alert: IdentityBackendHighErrorRate
          expr: rate(http_requests_total{status=~"5.."}[5m]) > 0.01
          for: 5m                   # ← Only fire if condition lasts 5 minutes
          labels:
            severity: critical
          annotations:
            summary: "Identity backend error rate above 1%"
```

**Flow:** Prometheus evaluates this expression every 30 seconds.
If the condition is true for 5+ minutes → fires alert → Alertmanager sends email.

---

## 8. Sealed Secrets — Deep Dive

### The Problem: Passwords in Git

You cannot commit `password=admin123` to a public Git repository.
But ArgoCD needs to read secrets from Git to deploy them.

### The Solution: Sealed Secrets

```
Your password (plain text)
    │
    ▼
kubeseal (encrypts using cluster's PUBLIC KEY)
    │
    ▼
Encrypted blob (safe to commit to Git)
    │
    ▼ (ArgoCD commits to Git, then applies to cluster)
    ▼
Sealed Secrets Controller (decrypts using cluster's PRIVATE KEY)
    │
    ▼
Regular Kubernetes Secret (available to pods as env vars)
```

### `platform/sealed-secrets-controller.yaml` — The Decryption Engine

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
spec:
  source:
    chart: sealed-secrets
    repoURL: https://bitnami-labs.github.io/sealed-secrets
```

This is an ArgoCD App that installs the Sealed Secrets controller via Helm.
The controller holds the **private key** and can decrypt any SealedSecret.

**CRITICAL:** If you delete the cluster, the private key is gone. You must back it up:
```powershell
kubectl get secret -n kube-system -l sealedsecrets.bitnami.com/sealed-secrets-key -o yaml
```

---

### `platform/identity-db/postgres/sealed-secret.yaml` — An Encrypted Secret

The file looks like this in Git:
```yaml
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: identity-postgres-secret
  namespace: identity
spec:
  encryptedData:
    POSTGRES_PASSWORD: AgB7K2x...  # ← Encrypted. Looks like gibberish. Safe to commit.
    POSTGRES_USER: AgC8L3y...      # ← Encrypted.
```

When applied to the cluster, the Sealed Secrets controller decrypts it into:
```yaml
kind: Secret
data:
  POSTGRES_PASSWORD: YWRtaW4xMjM=   # ← base64 of actual password
```

The pod then reads it as an environment variable:
```python
os.environ["POSTGRES_PASSWORD"]  # → "admin123"
```

---

### How Sealing Works (the `seal-dev-secrets.ps1` script)

```
# 1. Create a plain Kubernetes Secret (dry-run only, never applied)
kubectl create secret generic identity-postgres-secret \
  --from-literal=POSTGRES_PASSWORD=admin123 \
  --dry-run=client -o yaml > plain.yaml

# 2. Encrypt with kubeseal
kubeseal --format yaml < plain.yaml > sealed-secret.yaml

# 3. Delete plain text, commit encrypted version
rm plain.yaml
git add sealed-secret.yaml
git commit -m "add sealed secret"
```

---

## 9. Ingress — How URLs Reach Your Code

### The Full Journey of a Request

```
You type: http://identity.local/api/auth/login
              │
              ▼
C:\Windows\System32\drivers\etc\hosts
              127.0.0.1 identity.local    ← resolves to localhost
              │
              ▼
k3d port mapping: localhost:80 → k3d loadbalancer → NGINX Ingress pod
              │
              ▼
NGINX Ingress reads: infra/gitops/apps/identity/ingress.yaml
              host: identity.local
              path: /api(/|$)(.*)  → rewrites to /$2
              backend: identity-backend:8000
              │
              ▼
identity-backend FastAPI pod receives: GET /auth/login
              │
              ▼
FastAPI returns: {"access_token": "..."}
              │
              ▼
Back to browser ✅
```

### Why the `hosts` File?

`identity.local` is not a real domain. Your browser doesn't know where it lives.
The `hosts` file tells your computer: "when you see `identity.local`, use `127.0.0.1`
(i.e. your own machine)". Then k3d's port forwarding takes it from there.

### URL Map

| Type in Browser | Reaches | Explained |
|---|---|---|
| `http://identity.local/` | Identity React App | `identity-web` pod |
| `http://identity.local/api/...` | Identity FastAPI | `identity-backend` pod |
| `http://workspace.local/` | Workspace React App | `workspace-web` pod |
| `http://workspace.local/api/...` | Workspace FastAPI | `workspace-backend` pod |
| `http://argocd.local/` | ArgoCD Dashboard | ArgoCD server pod |
| `http://grafana.local/` | Grafana Dashboard | Grafana pod |
| `http://prometheus.local/` | Prometheus UI | Prometheus pod |

---

## 10. Kustomization Files — The Glue

### What Is Kustomize?

Kustomize reads `kustomization.yaml` and combines all listed files into one big
YAML document before applying to Kubernetes.

### Example: `infra/gitops/platform/kustomization.yaml`

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - sealed-secrets-controller.yaml   # ← Include this file
  - namespaces/                      # ← Namespaces first
  - identity-db/                     # ← Databases second
  - workspace-db/
```

**Without kustomize:** You'd need to `kubectl apply -f file1.yaml -f file2.yaml -f ...`
for every file, every time.

**With kustomize:** ArgoCD runs `kustomize build .` once and gets everything combined.

### The Subdirectory Pattern

When kustomize sees `- identity-postgres/` it looks inside that directory for its own
`kustomization.yaml` and processes that too. This creates a tree of references.

**Rule:** Every directory referenced in a `kustomization.yaml` MUST have its own
`kustomization.yaml` inside it. Missing one = `ComparisonError` in ArgoCD.

---

## 11. The Sync Wave System

Kubernetes resources get applied in wave order. Lower wave number = applied first.

```
Wave -1:  nginx-ingress      ← Traffic router must exist first
          sealed-secrets     ← Secret decryption must exist before secrets are created

Wave  0:  app-saas-platform-infra  ← Databases start (needs secrets controller from wave -1)

Wave  1:  app-identity       ← Identity service (needs DB from wave 0)
          app-workspace      ← Workspace service (needs DB and identity from wave 0)

Wave  2:  app-monitoring     ← Prometheus, Grafana (needs apps running to scrape)

Wave  3:  prometheus-rules   ← Alert rules (needs PrometheusRule CRD from wave 2)
```

**How to set a wave:**
```yaml
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "1"   # ← Wave number as a string
```

**Why this matters:** If you start the identity service before the database is ready,
the pod crashes on startup. Waves enforce ordering.

> [!WARNING]
> **Refactoring & Sync Waves**: If you change the folder structure (e.g., renaming `infra/` to `platform/`), ArgoCD will prune the old resources before creating the new ones. If these resources are PVCs, your data will be deleted. Always backup your databases before performing structural GitOps changes.

---

## 12. Full File Reference

### Quick Reference: Every YAML File and Its Job

| File | Kind | Job |
|---|---|---|
| `argocd/app-of-apps.yaml` | `Application` | Root — watches `argocd/` folder, creates all child apps |
| `argocd/app-saas-platform-infra.yaml` | `Application` | Points ArgoCD at `infra/gitops/platform/` |
| `argocd/app-identity.yaml` | `Application` | Points ArgoCD at `infra/gitops/apps/identity/` |
| `argocd/app-workspace.yaml` | `Application` | Points ArgoCD at `infra/gitops/apps/workspace/` |
| `argocd/app-monitoring.yaml` | `Application` | Points ArgoCD at `infra/gitops/monitoring/` |
| `argocd/nginx-ingress.yaml` | `Application` | Installs NGINX via Helm |
| `argocd/argocd-ingress.yaml` | `Ingress` | `argocd.local` → ArgoCD UI |
| `platform/sealed-secrets-controller.yaml` | `Application` | Installs Sealed Secrets via Helm |
| `platform/namespaces/...` | `Namespace` | Creates core namespaces (`identity`, `workspace`, etc.) |
| `platform/identity-db/postgres/pvc.yaml` | `PVC` | Reserves 5GB disk for PostgreSQL |
| `platform/identity-db/postgres/sealed-secret.yaml` | `SealedSecret` | Encrypted DB credentials |
| `platform/identity-db/identity-app-secret.yaml` | `SealedSecret` | Encrypted SMTP, Razorpay keys |
| `platform/identity-db/postgres/statefulset.yaml` | `StatefulSet` | Runs PostgreSQL pod |
| `platform/identity-db/postgres/service.yaml` | `Service` | DNS: `identity-postgres:5432` |
| `platform/identity-db/redis/...` | | Same pattern for Redis |
| `platform/workspace-db/sealed-secret.yaml` | `SealedSecret` | Encrypted MongoDB password |
| `infra/workspace-mongodb/workspace-app-secret.yaml` | `SealedSecret` | Encrypted SECRET_KEY, OAuth |
| `infra/workspace-mongodb/statefulset.yaml` | `StatefulSet` | Runs MongoDB pod |
| `apps/identity/configmap.yaml` | `ConfigMap` | Non-secret env: REDIS_URL, DOMAIN_NAME |
| `apps/identity/identity-backend-deployment.yaml` | `Deployment` | FastAPI app pods |
| `apps/identity/identity-backend-service.yaml` | `Service` | DNS: `identity-backend:8000` |
| `apps/identity/identity-backend-hpa.yaml` | `HPA` | Auto-scale 2→5 pods on CPU |
| `apps/identity/identity-web-deployment.yaml` | `Deployment` | React frontend pods |
| `apps/identity/ingress.yaml` | `Ingress` | `identity.local/api` → backend |
| `apps/workspace/...` | | Same pattern for workspace (port 8001) |
| `monitoring/kube-prometheus-stack/helmchart.yaml` | `Application` | Installs Prometheus+Grafana via Helm |
| `monitoring/kube-prometheus-stack/values.yaml` | Helm values | Configuration for Prometheus stack |
| `monitoring/loki-stack/helmchart.yaml` | `Application` | Installs Loki+Promtail via Helm |
| `monitoring/dashboards/platform-overview.yaml` | `ConfigMap` | Grafana dashboard auto-loaded |
| `monitoring/alerting/prometheus-rules.yaml` | `PrometheusRule` | Alert conditions |
| `monitoring/alerting/alertmanager-config.yaml` | `Secret` | Gmail SMTP for alerts |
| Every `kustomization.yaml` | `Kustomization` | Lists which files belong to this folder |

---

## 13. How It All Boots From Zero

When you run `bootstrap-local.ps1` for the first time, here is the exact order:

```
1. k3d creates a Kubernetes cluster inside Docker
   └─ Creates 3 containers: server, agent-0, agent-1

2. kubectl apply -f argocd/app-of-apps.yaml
   └─ This is the ONLY manual command!
   └─ ArgoCD is already running (installed by bootstrap script)

3. ArgoCD reads app-of-apps.yaml
   └─ It says "watch infra/gitops/argocd/"

4. ArgoCD reads all files in argocd/
   └─ Creates: nginx-ingress, sealed-secrets, app-infra,
               app-identity, app-workspace, app-monitoring

5. Wave -1 runs: nginx-ingress installs NGINX via Helm
                 sealed-secrets installs controller via Helm

6. Wave 0 runs: saas-platform-infra reads infra/gitops/platform/
   ├─ Creates namespace: identity, workspace
   ├─ Creates PVCs: reserves disk space
   ├─ Applies SealedSecrets → controller decrypts → creates Secrets
   ├─ Starts PostgreSQL pod (reads password from Secret)
   ├─ Starts Redis pod
   └─ Starts MongoDB pod

7. Wave 1 runs: app-identity reads infra/gitops/apps/identity/
   ├─ Applies ConfigMap (REDIS_URL, DOMAIN_NAME)
   ├─ Starts identity-backend pod (2 replicas)
   │   └─ Reads DB URL from Secret, REDIS_URL from ConfigMap
   ├─ Starts identity-web pod (React)
   └─ Creates Ingress rule: identity.local/api → identity-backend

8. Wave 1 runs: app-workspace (same as above for workspace)

9. Wave 2 runs: app-monitoring
   ├─ Creates monitoring namespace
   ├─ Installs kube-prometheus-stack Helm chart
   │   └─ Prometheus, Grafana, Alertmanager start
   ├─ Installs loki-stack Helm chart
   │   └─ Loki, Promtail start
   └─ Loads Grafana dashboard from ConfigMap

10. You open: http://identity.local    → See login page ✅
              http://grafana.local     → See dashboards ✅
              http://argocd.local      → See all apps green ✅
```

---

## Key Concepts Cheat Sheet

| If you need to... | Look at... |
|---|---|
| Change a database password | Re-seal the `sealed-secret.yaml`, commit |
| Change app config (URLs, ports) | Edit `configmap.yaml`, commit |
| Deploy a new Docker image | CI/CD updates `deployment.yaml` image tag, commit |
| Add a new service | Add it to `apps/`, add its ArgoCD app to `argocd/` |
| Debug a pod not starting | `kubectl describe pod <name> -n <namespace>` |
| See pod logs | `kubectl logs -n identity -l app=identity-backend` |
| Force ArgoCD to re-sync | `kubectl annotate app <name> -n argocd argocd.argoproj.io/refresh=normal --overwrite` |
| Check all app statuses | `kubectl get app -n argocd` |

---

## 14. Monitoring Deep Dive — Every Component Explained

> The entire monitoring stack is installed by one Helm chart: `kube-prometheus-stack`.
> It bundles 5 tools that work together. Understanding each one is key to using them.

---

### The Full Monitoring Data Flow

```
Your App Pod                       Kubernetes Cluster
┌─────────────────┐               ┌────────────────────────────────────────┐
│ identity-backend│               │        kube-state-metrics              │
│ /metrics endpoint│              │  "how many pods are running? replicas?"│
└────────┬────────┘               └───────────────┬────────────────────────┘
         │ expose numbers                         │ expose cluster state
         ▼                                        ▼
┌──────────────────────────────────────────────────────────────┐
│                     PROMETHEUS                               │
│  Scrapes /metrics from every pod every 15 seconds           │
│  Stores numbers in a time-series database (15 days)         │
└───────────────────────────┬──────────────────────────────────┘
                            │ query language (PromQL)
              ┌─────────────┴──────────────┐
              ▼                            ▼
┌─────────────────────┐      ┌─────────────────────────┐
│    GRAFANA          │      │    ALERTMANAGER          │
│  Draws charts from  │      │  Receives alert when    │
│  Prometheus data    │      │  Prometheus rule fires  │
│  http://grafana.local│     │  Sends you an email     │
└─────────────────────┘      └─────────────────────────┘

Separately — for logs (text output, not numbers):

┌─────────────┐    ┌──────────┐    ┌─────────┐    ┌──────────┐
│  Any Pod    │───▶│ Promtail │───▶│  Loki   │◀───│ Grafana  │
│ stdout logs │    │(DaemonSet│    │ log DB  │    │ Explore  │
└─────────────┘    │ on every │    └─────────┘    └──────────┘
                   │  node)   │
                   └──────────┘
```

---

### 1. Prometheus — The Metrics Brain

**What is it?**
Prometheus is a database that stores numbers over time. It is purpose-built for
metrics — things like "requests per second", "CPU usage %", "error count", "memory MB".

**What does it collect?**
Every 15 seconds, Prometheus makes an HTTP GET request to each pod's `/metrics`
endpoint. The response looks like:

```
# Counter: how many HTTP requests have been handled
http_requests_total{method="GET", status="200"} 1547
http_requests_total{method="POST", status="500"} 3

# Gauge: current memory in bytes
process_resident_memory_bytes 52428800

# Histogram: request duration distribution
http_request_duration_seconds_bucket{le="0.1"} 1423
http_request_duration_seconds_bucket{le="0.5"} 1498
http_request_duration_seconds_bucket{le="2.0"} 1547
```

**Why is it a pull model (Prometheus asks the app)?**
Not push (app sends to Prometheus). This is intentional:
- Prometheus controls the scrape rate — no app can flood it
- If a pod dies, Prometheus immediately detects it (no more data)
- New pods are auto-discovered — no registration needed

**Query Language: PromQL**
To use Prometheus data, you write PromQL expressions:
```promql
# Request rate over last 5 minutes
rate(http_requests_total[5m])

# Error percentage
rate(http_requests_total{status=~"5.."}[5m]) / rate(http_requests_total[5m]) * 100

# 99th percentile latency
histogram_quantile(0.99, rate(http_request_duration_seconds_bucket[5m]))
```

**Accessed at:** `http://prometheus.local`
**Stores data:** 15 days (configured in `values.yaml` `retention: 15d`)
**Uses PVC:** `10Gi` of disk for the time-series database

---

### 2. Grafana — The Dashboard UI

**What is it?**
Grafana is purely a visualization tool. It does NOT store any data. It connects to
data sources (Prometheus, Loki) and draws charts, graphs, and tables from them.

**Login:**
- URL: `http://grafana.local`
- Username: `admin`
- Password: `admin` (set in `values.yaml` → `adminPassword: "admin"`)

**What does it show?**
Anything you write a PromQL query for. Our `platform-overview.yaml` ConfigMap
pre-loads a dashboard with:
- Identity backend request rate (requests per second)
- Workspace backend request rate
- 5xx error count for both services
- Pod ready count per namespace
- p99 latency chart for both services

**How dashboards are auto-loaded:**
```
monitoring/dashboards/platform-overview.yaml
    │
    │ kind: ConfigMap
    │ labels:
    │   grafana_dashboard: "1"   ← magic label
    │
    ▼
Grafana sidecar container watches ALL ConfigMaps in monitoring namespace
    │ finds label grafana_dashboard: "1"
    ▼
Loads the JSON inside automatically into Grafana UI
    ← No clicking "Import" in the UI required
```

**Data Sources (pre-configured):**
- **Prometheus** — for all metrics (auto-configured by the Helm chart)
- **Loki** — for logs (added via `additionalDataSources` in `values.yaml`)

**Three containers in the Grafana pod:**
1. `grafana` — the main Grafana server
2. `grafana-sc-dashboard` — sidecar that watches ConfigMaps for dashboards
3. `grafana-sc-datasources` — sidecar that watches ConfigMaps for datasource config

---

### 3. Alertmanager — The Notification Engine

**What is it?**
Alertmanager receives alerts from Prometheus and decides who to notify, how, and when.

**Important distinction:**
- **Prometheus** decides WHEN an alert fires (evaluates the rule)
- **Alertmanager** decides WHERE to send it (email, Slack, PagerDuty, etc.)

**The flow:**
```
prometheus-rules.yaml defines:
  "If error rate > 1% for 5 minutes → fire alert called IdentityBackendHighErrorRate"
         │
         ▼
Prometheus evaluates this rule every 30 seconds
         │
         ▼ (condition is true for 5 minutes)
         ▼
Prometheus sends alert to Alertmanager
         │
         ▼
Alertmanager reads alertmanager-config.yaml:
  "Critical alerts → email to admin@gmail.com within 10 seconds"
  "Warning alerts  → email to admin@gmail.com, repeat every 6 hours"
         │
         ▼
Gmail receives the alert email ✅
```

**Key Alertmanager features:**
- **Grouping**: Bundles 50 alerts about the same service into 1 email
- **Inhibition**: If a pod is down, suppress its latency alerts (root cause known)
- **Silencing**: Snooze an alert for 2 hours during planned maintenance
- **Routing**: Different alert severities → different receivers

**Our alert rules (`prometheus-rules.yaml` — added after CRDs are installed):**

| Alert Name | Fires When | Severity |
|---|---|---|
| `IdentityBackendHighErrorRate` | Error rate > 1% for 5 min | Critical |
| `WorkspaceBackendHighErrorRate` | Error rate > 1% for 5 min | Critical |
| `IdentityBackendHighLatency` | p99 latency > 2s for 5 min | Warning |
| `WorkspaceBackendHighLatency` | p99 latency > 2s for 5 min | Warning |
| `PodCrashLooping` | Pod restarted > 3 times in 10 min | Critical |
| `PodNotReady` | Pod not Ready for 5 min | Warning |
| `PVCHighUsage` | Disk volume > 80% full | Warning |
| `HighMemoryUsage` | Container memory > 90% of limit | Warning |

**Accessed at:** `http://alertmanager.local`

---

### 4. Node Exporter — Hardware Metrics

**What is it?**
Node Exporter is a small program that runs on every Kubernetes **node** (physical
or virtual machine) and exposes hardware-level metrics.

**What does it collect?**
```
# CPU usage
node_cpu_seconds_total{cpu="0", mode="idle"} 7823.45

# Memory
node_memory_MemAvailable_bytes 1073741824   # 1GB free

# Disk
node_filesystem_avail_bytes{mountpoint="/"} 52428800

# Network
node_network_receive_bytes_total{device="eth0"} 1234567890
```

**How it runs:**
As a **DaemonSet** — one Node Exporter pod on every cluster node automatically.
In k3d you have 3 nodes (server + 2 agents), so you get 3 Node Exporter pods.

```bash
kubectl get pods -n monitoring | grep node-exporter
# kube-prometheus-stack-prometheus-node-exporter-gfrzk   1/1 Running  (node 1)
# kube-prometheus-stack-prometheus-node-exporter-xgxw6   1/1 Running  (node 2)
# kube-prometheus-stack-prometheus-node-exporter-zwg4f   1/1 Running  (node 3)
```

**Why is it separate from Prometheus?**
Prometheus collects APPLICATION metrics (from your code).
Node Exporter collects MACHINE metrics (CPU, disk, RAM of the host).
They're different concerns, so they're different tools.

**Grafana dashboards using it:** "Node CPU Usage", "Memory Available", "Disk I/O"

---

### 5. kube-state-metrics — Kubernetes State Metrics

**What is it?**
kube-state-metrics watches the Kubernetes API server and converts Kubernetes object
states into Prometheus metrics.

**The key difference from Node Exporter:**
```
Node Exporter:        "The machine has 2GB RAM free"  (hardware/OS)
kube-state-metrics:   "Pod identity-backend is in Pending state"  (K8s objects)
```

**What it exposes:**
```
# Is this deployment at its desired replica count?
kube_deployment_status_replicas{deployment="identity-backend"} 2
kube_deployment_status_replicas_available{deployment="identity-backend"} 2

# Pod phase
kube_pod_status_phase{pod="identity-backend-abc123", phase="Running"} 1

# Is the pod ready?
kube_pod_status_ready{pod="identity-backend-abc123", condition="true"} 1

# PVC usage
kube_persistentvolumeclaim_status_phase{pvc="identity-postgres-pvc"} "Bound"
```

**Why we need it:**
Without kube-state-metrics, Prometheus has no way to know if a Deployment has
the right number of replicas, or if a pod is crashing. It only knows what apps
expose themselves via /metrics.

kube-state-metrics bridges the gap — it translates the Kubernetes API into
Prometheus-compatible numbers.

**Used in our alert rules:**
```yaml
# PodNotReady alert uses kube-state-metrics data:
expr: kube_pod_status_ready{namespace=~"identity|workspace", condition="true"} == 0
```

---

### 6. Loki — Log Storage

**What is it?**
Loki is a log aggregation system built by Grafana Labs. It stores the text output
(stdout/stderr) from all your pods in a searchable, time-indexed database.

**How is it different from Prometheus?**
```
Prometheus: stores NUMBERS over time  (metrics)
            "request rate was 50 req/s at 2:00pm"

Loki:       stores TEXT over time  (logs)
            "2:00pm | ERROR | identity-backend | Database connection refused"
```

**Why use Loki instead of just `kubectl logs`?**
- `kubectl logs` only shows current pod — if the pod has restarted, old logs are gone
- Loki keeps ALL logs from ALL pods for days/weeks
- You can search across ALL services at once: "show me all lines containing ERROR from
  the last 2 hours across identity AND workspace namespaces"
- Grafana shows logs alongside metrics on the same dashboard

**Query Language: LogQL**
```logql
# All error logs from identity namespace in last 1 hour
{namespace="identity"} |= "ERROR"

# Logs from identity-backend containing "database"
{app="identity-backend"} |~ "(?i)database"

# Rate of error lines per minute
rate({namespace="identity"} |= "ERROR" [1m])
```

**Accessed via:** Grafana → Explore → Select "Loki" datasource

---

### 7. Promtail — The Log Collector

**What is it?**
Promtail is the agent that runs on every node, reads pod log files, and ships them
to Loki. Think of it as the "log shipper".

**How it runs:**
As a **DaemonSet** — one Promtail pod on every node, always.

```bash
kubectl get pods -n monitoring | grep promtail
# loki-stack-promtail-5ld5j   1/1 Running  (node 1)
# loki-stack-promtail-hjsks   1/1 Running  (node 2)
# loki-stack-promtail-m6trw   1/1 Running  (node 3)
```

**How it works:**
```
Pod identity-backend writes to stdout:
  "2026-04-17 02:00 | ERROR | Redis connection refused"
         │
         ▼  (Kubernetes writes stdout to a file on the node)
/var/log/pods/identity_identity-backend-abc_xxx/identity-backend/0.log
         │
         ▼  (Promtail reads this file continuously)
Promtail reads, attaches labels (namespace, pod, container)
         │
         ▼
Ships to Loki: http://loki-stack:3100
         │
         ▼
Loki stores → Grafana can query
```

**Automatic label attachment:**
Promtail automatically adds these labels to every log line:
- `namespace` = `identity`
- `pod` = `identity-backend-85f65d5d5-9r64d`
- `container` = `identity-backend`
- `app` = `identity-backend`

This is why LogQL `{namespace="identity"}` just works — no code changes in your app.

---

### How All 7 Monitoring Components Work Together

```
                        ┌─────────────────────────────┐
                        │     GRAFANA  (UI Layer)      │
                        │   http://grafana.local       │
                        │                              │
                        │  Dashboards ◄── ConfigMaps   │
                        │  (auto-loaded via sidecar)   │
                        └──────────┬──────────┬────────┘
                                   │          │
              ┌────────────────────▼─┐    ┌───▼────┐
              │     PROMETHEUS       │    │  LOKI  │
              │  Numbers database    │    │  Log   │
              │  http://prometheus   │    │  text  │
              │        .local        │    │   DB   │
              └──┬────────┬──────────┘    └───▲────┘
                 │        │                   │
        ┌────────▼─┐  ┌───▼──────────┐   ┌───┴──────┐
        │ALERTMANAGER│ │ SCRAPERS     │   │ PROMTAIL │
        │Sends emails│ │             │   │(DaemonSet│
        │http://alert│ │ node-exporter│  │ per node)│
        │manager.local│ │kube-state-  │  └──────────┘
        └────────────┘ │ metrics     │
                       │ your /metrics│
                       └─────────────┘
```

---

### What To Look At When Something Goes Wrong

| Symptom | Tool | What to check |
|---|---|---|
| Pod is crashing | **Loki** | Search `{app="identity-backend"} \|= "ERROR"` |
| High CPU on a node | **Node Exporter → Grafana** | Node CPU dashboard |
| Deployment stuck at 1/2 ready | **kube-state-metrics → Prometheus** | `kube_deployment_status_replicas_available` |
| API error rate spike | **Prometheus** | `rate(http_requests_total{status=~"5.."}[5m])` |
| Got an alert email | **Alertmanager** | `http://alertmanager.local` — see what fired |
| Want to explore logs | **Grafana Explore** | Select Loki, use LogQL |

---

### Grafana Login & First Steps

```
URL:      http://grafana.local
Username: admin
Password: admin
```

**Step 1 — View the Platform Dashboard:**
Grafana → Dashboards → Browse → "SaaS Platform — Overview"
(Auto-loaded from `monitoring/dashboards/platform-overview.yaml`)

**Step 2 — Explore Logs:**
Grafana → Explore → Select "Loki" datasource
Enter: `{namespace="identity"}` → Run Query

**Step 3 — Write a PromQL query:**
Grafana → Explore → Select "Prometheus" datasource
Enter: `rate(http_requests_total[5m])` → Run Query

**Step 4 — See active alerts:**
Grafana → Alerting → Alert Rules  (or visit `http://alertmanager.local`)

---

## 15. kubectl Command Reference

> **Read this like a dictionary.** Find what you need, copy the command.
> Replace `<name>`, `<namespace>`, `<image>` with real values from your cluster.

---

### 🔍 GET — View Resources

```bash
# ── List ALL ArgoCD apps and their status ─────────────────────────────────────
kubectl get app -n argocd

# ── List pods in a namespace ──────────────────────────────────────────────────
kubectl get pods -n identity
kubectl get pods -n workspace
kubectl get pods -n monitoring
kubectl get pods -n argocd
kubectl get pods -n ingress-nginx

# ── List pods across ALL namespaces ───────────────────────────────────────────
kubectl get pods -A

# ── List pods with extra info (node, IP) ──────────────────────────────────────
kubectl get pods -n identity -o wide

# ── List all services (internal DNS entries) ──────────────────────────────────
kubectl get svc -n identity
kubectl get svc -n workspace
kubectl get svc -A

# ── List all Ingress rules ────────────────────────────────────────────────────
kubectl get ingress -A

# ── List persistent volumes and claims ───────────────────────────────────────
kubectl get pvc -A
kubectl get pv

# ── List ConfigMaps ───────────────────────────────────────────────────────────
kubectl get configmap -n identity
kubectl get configmap -n monitoring

# ── List Secrets (names only — values are hidden) ────────────────────────────
kubectl get secret -n identity
kubectl get secret -n workspace

# ── List all namespaces ───────────────────────────────────────────────────────
kubectl get namespace

# ── List nodes in the cluster ─────────────────────────────────────────────────
kubectl get nodes
kubectl get nodes -o wide     # shows IP, OS, kernel version

# ── List deployments ──────────────────────────────────────────────────────────
kubectl get deployment -n identity
kubectl get deployment -n workspace

# ── List statefulsets (databases) ─────────────────────────────────────────────
kubectl get statefulset -n identity
kubectl get statefulset -n workspace

# ── List HorizontalPodAutoscalers ─────────────────────────────────────────────
kubectl get hpa -n identity
kubectl get hpa -n workspace
```

---

### 📋 DESCRIBE — Deep Inspection

```bash
# ── Describe a pod (shows events, env vars, image, error reasons) ─────────────
kubectl describe pod <pod-name> -n identity
# Example:
kubectl describe pod identity-backend-85f65d5d5-9r64d -n identity

# ── Describe a deployment ─────────────────────────────────────────────────────
kubectl describe deployment identity-backend -n identity
kubectl describe deployment workspace-backend -n workspace

# ── Describe a service ────────────────────────────────────────────────────────
kubectl describe svc identity-backend -n identity

# ── Describe an ingress (shows routing rules) ─────────────────────────────────
kubectl describe ingress identity-ingress-api -n identity

# ── Describe a node ───────────────────────────────────────────────────────────
kubectl describe node k3d-saas-cluster-server-0

# ── Describe a PVC (shows if Bound or Pending) ───────────────────────────────
kubectl describe pvc identity-postgres-pvc -n identity

# ── Describe a sealed secret (shows decrypt error if any) ────────────────────
kubectl describe sealedsecret identity-postgres-secret -n identity

# ── Describe an ArgoCD app (shows all resources and their sync status) ────────
kubectl describe app app-infra -n argocd
```

---

### 📜 LOGS — View Pod Output

```bash
# ── Get logs from a pod ───────────────────────────────────────────────────────
kubectl logs <pod-name> -n identity

# ── Stream logs live (follow) ────────────────────────────────────────────────
kubectl logs -f <pod-name> -n identity

# ── Get last 100 lines ────────────────────────────────────────────────────────
kubectl logs <pod-name> -n identity --tail=100

# ── Logs from ALL pods of a deployment (by label) ────────────────────────────
kubectl logs -n identity -l app=identity-backend
kubectl logs -n workspace -l app=workspace-backend

# ── Stream logs from ALL pods of a deployment ────────────────────────────────
kubectl logs -n identity -l app=identity-backend -f

# ── Logs from a specific container inside a multi-container pod ───────────────
kubectl logs <pod-name> -n monitoring -c grafana
kubectl logs <pod-name> -n monitoring -c grafana-sc-dashboard

# ── Logs from a pod that previously crashed (previous instance) ───────────────
kubectl logs <pod-name> -n identity --previous

# ── Get logs since last 30 minutes ────────────────────────────────────────────
kubectl logs <pod-name> -n identity --since=30m
```

---

### ⚡ APPLY — Deploy or Update Resources

```bash
# ── Apply a single YAML file ──────────────────────────────────────────────────
kubectl apply -f infra/gitops/apps/identity/ingress.yaml

# ── Apply an entire directory ─────────────────────────────────────────────────
kubectl apply -f infra/gitops/apps/identity/

# ── Apply using kustomize (same as ArgoCD does internally) ───────────────────
kubectl apply -k infra/gitops/apps/identity/

# ── Dry-run — see what WOULD be applied without actually doing it ─────────────
kubectl apply -f <file.yaml> --dry-run=client
kubectl apply -k infra/gitops/apps/identity/ --dry-run=client

# ── Force replace a resource (deletes and recreates) ─────────────────────────
kubectl replace --force -f <file.yaml>
```

---

### 🗑️ DELETE — Remove Resources

```bash
# ── Delete a pod (Kubernetes recreates it automatically) ──────────────────────
kubectl delete pod <pod-name> -n identity

# ── Force delete a stuck/terminating pod ─────────────────────────────────────
kubectl delete pod <pod-name> -n identity --force --grace-period=0

# ── Delete a deployment ───────────────────────────────────────────────────────
kubectl delete deployment identity-backend -n identity

# ── Delete an ingress ────────────────────────────────────────────────────────
kubectl delete ingress identity-ingress -n identity

# ── Delete from YAML file ────────────────────────────────────────────────────
kubectl delete -f <file.yaml>
```

---

### 🔬 EXEC — Run Commands Inside a Pod

```bash
# ── Open an interactive shell inside a pod ────────────────────────────────────
kubectl exec -it <pod-name> -n identity -- /bin/sh
kubectl exec -it <pod-name> -n identity -- /bin/bash

# ── Run a single command inside a pod ────────────────────────────────────────
kubectl exec -n identity <pod-name> -- ls /app
kubectl exec -n identity <pod-name> -- env | grep DATABASE

# ── Test database connection from inside a pod ────────────────────────────────
kubectl exec -it identity-postgres-0 -n identity -- psql -U postgres -d identitydb

# ── Test Redis from inside a pod ──────────────────────────────────────────────
kubectl exec -it identity-redis-0 -n identity -- redis-cli ping

# ── Test MongoDB from inside a pod ────────────────────────────────────────────
kubectl exec -it workspace-mongodb-0 -n workspace -- mongosh
```

---

### 🌐 PORT-FORWARD — Access Services Directly (bypassing Ingress)

```bash
# ── Access identity backend directly on localhost:8000 ────────────────────────
kubectl port-forward -n identity svc/identity-backend 8000:8000

# ── Access workspace backend directly on localhost:8001 ───────────────────────
kubectl port-forward -n workspace svc/workspace-backend 8001:8001

# ── Access PostgreSQL directly on localhost:5432 ──────────────────────────────
kubectl port-forward -n identity svc/identity-postgres 5432:5432

# ── Access Redis directly on localhost:6379 ───────────────────────────────────
kubectl port-forward -n identity svc/identity-redis 6379:6379

# ── Access MongoDB directly on localhost:27017 ────────────────────────────────
kubectl port-forward -n workspace svc/workspace-mongodb 27017:27017

# ── Access Grafana directly (useful if Ingress is broken) ────────────────────
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
# Then open: http://localhost:3000

# ── Access Prometheus directly ────────────────────────────────────────────────
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
# Then open: http://localhost:9090
```

---

### 📊 TOP — Resource Usage (CPU & Memory)

```bash
# ── CPU and memory usage per node ────────────────────────────────────────────
kubectl top nodes

# ── CPU and memory usage per pod ─────────────────────────────────────────────
kubectl top pods -n identity
kubectl top pods -n workspace
kubectl top pods -n monitoring
kubectl top pods -A           # all namespaces

# ── Sort pods by CPU usage ────────────────────────────────────────────────────
kubectl top pods -A --sort-by=cpu

# ── Sort pods by memory usage ─────────────────────────────────────────────────
kubectl top pods -A --sort-by=memory
```

---

### 🔄 ROLLOUT — Deployments

```bash
# ── Check rollout status ─────────────────────────────────────────────────────
kubectl rollout status deployment/identity-backend -n identity
kubectl rollout status deployment/workspace-backend -n workspace

# ── See rollout history ───────────────────────────────────────────────────────
kubectl rollout history deployment/identity-backend -n identity

# ── Rollback to the previous version ─────────────────────────────────────────
kubectl rollout undo deployment/identity-backend -n identity

# ── Restart all pods in a deployment (without changing anything) ─────────────
kubectl rollout restart deployment/identity-backend -n identity
kubectl rollout restart deployment/workspace-backend -n workspace
# Use this after: changing a ConfigMap or Secret (pods don't auto-restart otherwise)
```

---

### 🔐 SECRETS — Read / Debug

```bash
# ── List secrets in a namespace ───────────────────────────────────────────────
kubectl get secret -n identity

# ── See what keys a secret contains (not values) ─────────────────────────────
kubectl get secret identity-postgres-secret -n identity -o jsonpath='{.data}' | python -c "import sys,json; [print(k) for k in json.load(sys.stdin)]"

# ── Decode a specific secret value ────────────────────────────────────────────
# PowerShell:
$b64 = kubectl get secret identity-postgres-secret -n identity -o jsonpath='{.data.POSTGRES_PASSWORD}'
[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($b64))

# ── See all environment variables a pod has (includes secrets) ────────────────
kubectl exec <pod-name> -n identity -- env

# ── List SealedSecrets and their decrypt status ───────────────────────────────
kubectl get sealedsecret -n identity
kubectl describe sealedsecret identity-postgres-secret -n identity
```

---

### 🚀 ArgoCD CLI — GitOps Operations

```bash
# ── See all apps ─────────────────────────────────────────────────────────────
argocd app list --server argocd.local --insecure --grpc-web

# ── Get detail on one app ─────────────────────────────────────────────────────
argocd app get saas-platform-infra --server argocd.local --insecure --grpc-web

# ── Manually sync an app (pull latest Git changes NOW) ───────────────────────
argocd app sync app-identity --server argocd.local --insecure --grpc-web
argocd app sync app-monitoring --server argocd.local --insecure --grpc-web
argocd app sync saas-platform-infra --server argocd.local --insecure --grpc-web

# ── Force a hard refresh (re-reads Git, ignores cache) ───────────────────────
kubectl annotate app app-monitoring -n argocd argocd.argoproj.io/refresh=hard --overwrite

# ── Terminate a stuck sync operation ─────────────────────────────────────────
argocd app terminate-op app-monitoring --server argocd.local --insecure --grpc-web

# ── Sync ALL apps at once ─────────────────────────────────────────────────────
argocd app sync -l argocd.argoproj.io/app --server argocd.local --insecure --grpc-web
```

---

### 🆘 Emergency Commands

```bash
# ── Something is wrong — what's happening in a namespace? ─────────────────────
kubectl get events -n identity --sort-by='.lastTimestamp'
kubectl get events -n workspace --sort-by='.lastTimestamp'
kubectl get events -A --sort-by='.lastTimestamp' | tail -20

# ── Pod stuck in Pending — why? ───────────────────────────────────────────────
kubectl describe pod <pod-name> -n identity | grep -A 5 "Events:"

# ── Pod in CrashLoopBackOff — what's the error? ──────────────────────────────
kubectl logs <pod-name> -n identity --previous
kubectl describe pod <pod-name> -n identity

# ── Pod in CreateContainerConfigError — missing secret or configmap ───────────
kubectl describe pod <pod-name> -n identity
# Look for: "secret X not found" or "configmap Y not found"

# ── Ingress not routing — check NGINX controller logs ────────────────────────
kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller --tail=50

# ── ArgoCD stuck syncing — force unlock ──────────────────────────────────────
argocd app terminate-op <app-name> --server argocd.local --insecure --grpc-web

# ── Database pod lost data after restart (PVC check) ─────────────────────────
kubectl get pvc -n identity
kubectl describe pvc identity-postgres-pvc -n identity
# Status must say "Bound" — if "Pending", storage provisioner failed

# ── Nuclear option: delete and recreate a pod ─────────────────────────────────
kubectl delete pod <pod-name> -n identity --force --grace-period=0
# Kubernetes auto-recreates it from the Deployment/StatefulSet spec

# ── Check cluster resource capacity ───────────────────────────────────────────
kubectl describe nodes | grep -A 5 "Allocated resources"
```

---

### 📌 This Cluster's Namespaces Reference

| Namespace | What lives there | View with |
|---|---|---|
| `identity` | FastAPI backend, React frontend, PostgreSQL, Redis | `kubectl get pods -n identity` |
| `workspace` | Node.js backend, React frontend, MongoDB | `kubectl get pods -n workspace` |
| `monitoring` | Prometheus, Grafana, Alertmanager, Loki, Promtail | `kubectl get pods -n monitoring` |
| `argocd` | ArgoCD server, repo-server, application-controller | `kubectl get pods -n argocd` |
| `ingress-nginx` | NGINX Ingress Controller | `kubectl get pods -n ingress-nginx` |
| `kube-system` | Sealed Secrets controller, CoreDNS | `kubectl get pods -n kube-system` |

---

### 📌 This Cluster's Services Reference

| Service DNS | Port | What it is |
|---|---|---|
| `identity-postgres.identity.svc` | 5432 | PostgreSQL |
| `identity-redis.identity.svc` | 6379 | Redis |
| `identity-backend.identity.svc` | 8000 | FastAPI |
| `identity-web.identity.svc` | 80 | React (NGINX) |
| `workspace-mongodb.workspace.svc` | 27017 | MongoDB |
| `workspace-backend.workspace.svc` | 8001 | Node.js backend |
| `workspace-web.workspace.svc` | 80 | React (NGINX) |
| `kube-prometheus-stack-grafana.monitoring.svc` | 80 | Grafana |
| `kube-prometheus-stack-prometheus.monitoring.svc` | 9090 | Prometheus |
| `loki-stack.monitoring.svc` | 3100 | Loki |


