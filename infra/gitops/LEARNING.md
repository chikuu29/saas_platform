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
│   ├── app-infra.yaml               ← Manages: databases + secrets
│   ├── app-identity.yaml            ← Manages: identity service
│   ├── app-workspace.yaml           ← Manages: workspace service
│   ├── app-monitoring.yaml          ← Manages: Prometheus + Grafana
│   ├── nginx-ingress.yaml           ← Manages: NGINX traffic router
│   └── argocd-ingress.yaml          ← Makes ArgoCD UI accessible
│
├── infra/                           ← Layer 2: Databases & infrastructure
│   ├── kustomization.yaml           ← Tells kustomize which files to include
│   ├── sealed-secrets-controller.yaml ← The secret decryption engine
│   ├── identity-postgres/           ← PostgreSQL for identity service
│   │   ├── kustomization.yaml
│   │   ├── namespace.yaml           ← Creates the 'identity' namespace
│   │   ├── pvc.yaml                 ← Reserves disk space for data
│   │   ├── sealed-secret.yaml       ← Encrypted DB credentials
│   │   ├── identity-app-secret.yaml ← Encrypted SMTP, Razorpay keys
│   │   ├── statefulset.yaml         ← Runs the PostgreSQL pod
│   │   └── service.yaml             ← Internal DNS: identity-postgres:5432
│   ├── identity-redis/              ← Redis for sessions/caching
│   │   └── (same pattern)
│   └── workspace-mongodb/           ← MongoDB for workspace service
│       └── (same pattern)
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

### `argocd/app-infra.yaml` — Databases (Sync Wave 0)

Deploys all databases. Must run before apps because apps need databases ready to start.

```yaml
spec:
  source:
    path: infra/gitops/infra          # ← Watches the infra/ folder
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

### `infra/sealed-secrets-controller.yaml` — The Decryption Engine

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

### `infra/identity-postgres/sealed-secret.yaml` — An Encrypted Secret

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

### Example: `infra/gitops/infra/kustomization.yaml`

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - sealed-secrets-controller.yaml   # ← Include this file
  - identity-postgres/               # ← Include entire directory (reads its kustomization.yaml)
  - identity-redis/
  - workspace-mongodb/
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

Wave  0:  app-infra          ← Databases start (needs secrets controller from wave -1)

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

---

## 12. Full File Reference

### Quick Reference: Every YAML File and Its Job

| File | Kind | Job |
|---|---|---|
| `argocd/app-of-apps.yaml` | `Application` | Root — watches `argocd/` folder, creates all child apps |
| `argocd/app-infra.yaml` | `Application` | Points ArgoCD at `infra/gitops/infra/` |
| `argocd/app-identity.yaml` | `Application` | Points ArgoCD at `infra/gitops/apps/identity/` |
| `argocd/app-workspace.yaml` | `Application` | Points ArgoCD at `infra/gitops/apps/workspace/` |
| `argocd/app-monitoring.yaml` | `Application` | Points ArgoCD at `infra/gitops/monitoring/` |
| `argocd/nginx-ingress.yaml` | `Application` | Installs NGINX via Helm |
| `argocd/argocd-ingress.yaml` | `Ingress` | `argocd.local` → ArgoCD UI |
| `infra/sealed-secrets-controller.yaml` | `Application` | Installs Sealed Secrets via Helm |
| `infra/identity-postgres/namespace.yaml` | `Namespace` | Creates `identity` namespace |
| `infra/identity-postgres/pvc.yaml` | `PVC` | Reserves 5GB disk for PostgreSQL |
| `infra/identity-postgres/sealed-secret.yaml` | `SealedSecret` | Encrypted DB credentials |
| `infra/identity-postgres/identity-app-secret.yaml` | `SealedSecret` | Encrypted SMTP, Razorpay keys |
| `infra/identity-postgres/statefulset.yaml` | `StatefulSet` | Runs PostgreSQL pod |
| `infra/identity-postgres/service.yaml` | `Service` | DNS: `identity-postgres:5432` |
| `infra/identity-redis/...` | | Same pattern for Redis |
| `infra/workspace-mongodb/sealed-secret.yaml` | `SealedSecret` | Encrypted MongoDB password |
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

6. Wave 0 runs: app-infra reads infra/gitops/infra/
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
