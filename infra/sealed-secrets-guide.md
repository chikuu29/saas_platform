# SealedSecrets Guide

Operational reference for creating, managing, and troubleshooting SealedSecrets
in the SaaS platform GitOps cluster.

---

## How It Works

```
You (plaintext values)
      │
      ▼
kubectl create secret --dry-run   ← never saved to disk permanently
      │
      ▼ kubeseal encrypts using cluster PUBLIC key
SealedSecret YAML  ← ✅ safe to commit to Git
      │
      ▼ ArgoCD syncs → applies to cluster
Sealed Secrets Controller (kube-system)
      │ decrypts using cluster PRIVATE key (never leaves cluster)
      ▼
Normal Kubernetes Secret  ← ✅ lives only inside the cluster
      │
      ▼ envFrom / secretRef
Pod Environment Variables
```

**Key principle:** Only the cluster can decrypt a SealedSecret.
The private key never leaves `kube-system`. Encrypted YAML is safe to store in Git.

---

## Cluster Setup

The controller is already deployed at:

```
infra/gitops/platform/sealed-secrets-controller.yaml
```

| Detail               | Value                       |
| :------------------- | :-------------------------- |
| Controller Name      | `sealed-secrets-controller` |
| Controller Namespace | `kube-system`               |
| CRD Kind             | `SealedSecret`              |
| API Group            | `bitnami.com/v1alpha1`      |

Verify it is running:

**PowerShell / CMD**
```powershell
kubectl get pods -n kube-system -l app.kubernetes.io/name=sealed-secrets
```

**Linux / macOS**
```bash
kubectl get pods -n kube-system -l app.kubernetes.io/name=sealed-secrets
```

---

## Creating a New SealedSecret

### Step 1 — Create a temporary plaintext Secret

> ⚠️ **Never commit `temp-secret.yaml`.** It contains plaintext values encoded in base64.
> Delete it immediately after sealing (Step 3).

**PowerShell** *(use `| Set-Content -Encoding utf8` — NOT `>` — to avoid UTF-16 LE encoding bug)*
```powershell
kubectl create secret generic <secret-name> `
  --from-literal=KEY_ONE=value1 `
  --from-literal=KEY_TWO=value2 `
  --namespace=<target-namespace> `
  --dry-run=client -o yaml | Set-Content -Encoding utf8 temp-secret.yaml
```

**CMD**
```cmd
kubectl create secret generic <secret-name> ^
  --from-literal=KEY_ONE=value1 ^
  --from-literal=KEY_TWO=value2 ^
  --namespace=<target-namespace> ^
  --dry-run=client -o yaml > temp-secret.yaml
```

**Linux / macOS**
```bash
kubectl create secret generic <secret-name> \
  --from-literal=KEY_ONE=value1 \
  --from-literal=KEY_TWO=value2 \
  --namespace=<target-namespace> \
  --dry-run=client -o yaml > temp-secret.yaml
```

> **Windows encoding note:** PowerShell's `>` operator writes UTF-16 LE by default.
> `kubeseal` cannot parse UTF-16 and will silently produce an empty output file.
> Always use `| Set-Content -Encoding utf8` in PowerShell.

---

### Step 2 — Seal the Secret

**PowerShell**
```powershell
kubeseal --controller-namespace kube-system `
  --controller-name sealed-secrets-controller `
  --format yaml `
  -f temp-secret.yaml `
  -w infra\gitops\platform\identity-db\postgres\<secret-name>.yaml
```

**CMD**
```cmd
kubeseal --controller-namespace kube-system ^
  --controller-name sealed-secrets-controller ^
  --format yaml ^
  -f temp-secret.yaml ^
  -w infra\gitops\platform\identity-db\postgres\<secret-name>.yaml
```

**Linux / macOS**
```bash
kubeseal --controller-namespace kube-system \
  --controller-name sealed-secrets-controller \
  --format yaml \
  -f temp-secret.yaml \
  -w infra/gitops/platform/identity-db/postgres/<secret-name>.yaml
```

The output file is encrypted — safe to commit to Git.

---

### Step 3 — Delete the plaintext file

**PowerShell**
```powershell
Remove-Item temp-secret.yaml
```

**CMD**
```cmd
del temp-secret.yaml
```

**Linux / macOS**
```bash
rm temp-secret.yaml
```

---

## Updating an Existing SealedSecret (Partial Update)

> You do **not** need to re-seal all keys just to update one value.
> Use `--merge-into` to update only the keys that changed.

### Option A — `--merge-into` (Recommended)

Only the specified key gets re-encrypted and merged. All other keys in the existing SealedSecret file are left untouched.

**PowerShell**
```powershell
# Step 1: Generate temp secret with ONLY the key(s) you want to update
kubectl create secret generic <secret-name> `
  --from-literal=SECRET_KEY=new-value-here `
  --namespace=<namespace> `
  --dry-run=client -o yaml | Set-Content -Encoding utf8 temp-secret.yaml

# Step 2: Merge — only updates SECRET_KEY, leaves all other keys unchanged
kubeseal --controller-namespace kube-system `
  --controller-name sealed-secrets-controller `
  --format yaml `
  -f temp-secret.yaml `
  --merge-into infra\gitops\platform\identity-db\postgres\<secret-name>.yaml

# Step 3: Cleanup
Remove-Item temp-secret.yaml
```

**CMD**
```cmd
kubectl create secret generic <secret-name> ^
  --from-literal=SECRET_KEY=new-value-here ^
  --namespace=<namespace> ^
  --dry-run=client -o yaml > temp-secret.yaml && ^
kubeseal --controller-namespace kube-system ^
  --controller-name sealed-secrets-controller ^
  --format yaml ^
  -f temp-secret.yaml ^
  --merge-into infra\gitops\platform\identity-db\postgres\<secret-name>.yaml && ^
del temp-secret.yaml
```

**Linux / macOS**
```bash
kubectl create secret generic <secret-name> \
  --from-literal=SECRET_KEY=new-value-here \
  --namespace=<namespace> \
  --dry-run=client -o yaml \
| kubeseal \
  --controller-namespace kube-system \
  --controller-name sealed-secrets-controller \
  --format yaml \
  --merge-into infra/gitops/platform/identity-db/postgres/<secret-name>.yaml
```

---

### Option B — `--raw` (Encrypt a Single Value Inline)

Encrypts one raw value without creating a temp file. Copy the output and paste it directly into `encryptedData` in the SealedSecret YAML.

**PowerShell**
```powershell
"new-value-here" | kubeseal --raw `
  --name <secret-name> `
  --namespace <namespace> `
  --controller-namespace kube-system `
  --controller-name sealed-secrets-controller
# Copy the output → paste into encryptedData.YOUR_KEY in the yaml file
```

**Linux / macOS**
```bash
echo -n "new-value-here" | kubeseal --raw \
  --name <secret-name> \
  --namespace <namespace> \
  --controller-namespace kube-system \
  --controller-name sealed-secrets-controller
# Copy the output → paste into encryptedData.YOUR_KEY in the yaml file
```

---

### When to Use Which Approach

| Approach | Use When |
| :--- | :--- |
| **Re-seal all keys** | First time creating the secret |
| **`--merge-into`** ✅ | Updating/rotating one or a few specific keys |
| **`--raw`** | Quickly patching a single value directly into the YAML |

---

### Step 4 — Register in kustomization.yaml

```yaml
# infra/gitops/platform/identity-db/postgres/kustomization.yaml
resources:
  - <secret-name>.yaml   # ← add this line
```

---

### Step 5 — Reference in Deployment

```yaml
# deployment.yaml
envFrom:
  - secretRef:
      name: <secret-name>   # must match metadata.name in the SealedSecret
```

---

### Step 6 — Commit and push

**PowerShell / CMD**
```powershell
git add infra/gitops/platform/identity-db/postgres/<secret-name>.yaml
git add infra/gitops/platform/identity-db/postgres/kustomization.yaml
git commit -m "feat: add <secret-name> sealed secret"
git push
```

**Linux / macOS**
```bash
git add infra/gitops/platform/identity-db/postgres/<secret-name>.yaml
git add infra/gitops/platform/identity-db/postgres/kustomization.yaml
git commit -m "feat: add <secret-name> sealed secret"
git push
```

ArgoCD will detect the change and apply it automatically.

---

## Complete One-Liner Workflow

### PowerShell (Recommended for Windows)

```powershell
# All-in-one: generate → seal → cleanup
kubectl create secret generic <secret-name> `
  --from-literal=KEY_ONE=value1 `
  --from-literal=KEY_TWO=value2 `
  --namespace=<namespace> `
  --dry-run=client -o yaml | Set-Content -Encoding utf8 temp-secret.yaml; `
kubeseal --controller-namespace kube-system `
  --controller-name sealed-secrets-controller `
  --format yaml `
  -f temp-secret.yaml `
  -w infra\gitops\platform\identity-db\postgres\<secret-name>.yaml; `
Remove-Item temp-secret.yaml
```

### CMD

```cmd
kubectl create secret generic <secret-name> ^
  --from-literal=KEY_ONE=value1 ^
  --from-literal=KEY_TWO=value2 ^
  --namespace=<namespace> ^
  --dry-run=client -o yaml > temp-secret.yaml && ^
kubeseal --controller-namespace kube-system ^
  --controller-name sealed-secrets-controller ^
  --format yaml ^
  -f temp-secret.yaml ^
  -w infra\gitops\platform\identity-db\postgres\<secret-name>.yaml && ^
del temp-secret.yaml
```

### Linux / macOS

```bash
kubectl create secret generic <secret-name> \
  --from-literal=KEY_ONE=value1 \
  --from-literal=KEY_TWO=value2 \
  --namespace=<namespace> \
  --dry-run=client -o yaml \
| kubeseal \
  --controller-namespace kube-system \
  --controller-name sealed-secrets-controller \
  --format yaml \
  > infra/gitops/apps/<folder>/<secret-name>.yaml
# No temp file needed — Linux pipes directly into kubeseal
```

> **Linux advantage:** On Linux/macOS you can pipe `kubectl` output directly into `kubeseal`
> without creating a temp file at all, since there is no encoding issue.

---

## Real Examples in This Project

### `workspace-app-secret` — Workspace Backend App Credentials

**Location:** `infra/gitops/apps/workspace/workspace-app-secret.yaml`
**Namespace:** `workspace`

| Key                   | Description                              |
| :-------------------- | :--------------------------------------- |
| `OAUTH_CLIENT_ID`     | OAuth2 client ID registered on Identity  |
| `OAUTH_CLIENT_SECRET` | OAuth2 client secret                     |
| `SECRET_KEY`          | App signing secret for tokens/sessions   |

**Referenced by:**

```yaml
# workspace-backend-deployment.yaml
envFrom:
  - secretRef:
      name: workspace-app-secret
```

---

### `workspace-mongodb-secret` — MongoDB Connection

**Location:** `infra/gitops/platform/workspace-db/sealed-secret.yaml`
**Namespace:** `workspace`

| Key         | Description                    |
| :---------- | :----------------------------- |
| `MONGO_URI` | Full MongoDB connection string  |

---

## SealedSecret YAML Anatomy

```yaml
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: my-secret           # ← the decrypted Secret will have this same name
  namespace: workspace      # ← IMPORTANT: sealed to this namespace only
spec:
  encryptedData:
    MY_KEY: AgBx9...        # ← encrypted value (safe in Git)
  template:
    metadata:
      name: my-secret
      namespace: workspace
```

What the controller **automatically creates** inside the cluster:

```yaml
# Auto-created — you never write this manually
apiVersion: v1
kind: Secret
metadata:
  name: my-secret
  namespace: workspace
data:
  MY_KEY: <base64 of decrypted value>
```

---

## Critical Rules

| Rule | Reason |
| :--- | :----- |
| **Namespace must match** | A secret sealed for `workspace` cannot be decrypted in `identity`. If changing namespace, re-seal from scratch. |
| **Never commit plaintext** | Add `temp-secret.yaml` to `.gitignore` as a safety net. |
| **`kubeseal` needs cluster access** | It fetches the public key via `kubectl`. Ensure your kubeconfig points to the correct cluster. |
| **Rotating a value = re-sealing** | Decrypt is one-way in Git. To update a value, create a new plaintext secret with the new value and re-run `kubeseal`. |
| **Controller name must match** | Always pass `--controller-name sealed-secrets-controller --controller-namespace kube-system`. |
| **PowerShell encoding** | Use `\| Set-Content -Encoding utf8` not `>` — PowerShell `>` creates UTF-16 LE which kubeseal cannot parse. |
| **One controller only** | Do not run multiple Sealed Secrets controllers — each generates its own key pair and secrets are not cross-decryptable. |

---

## Verification Commands

### PowerShell

```powershell
# 1. Check the SealedSecret was accepted by controller
kubectl get sealedsecret <secret-name> -n <namespace>

# 2. Check the decrypted Secret was created
kubectl get secret <secret-name> -n <namespace>

# 3. List all keys inside the Secret (values are base64, not shown)
kubectl get secret <secret-name> -n <namespace> -o yaml

# 4. Decode a specific key value
$encoded = kubectl get secret <secret-name> -n <namespace> `
  -o jsonpath="{.data.MY_KEY}"
[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($encoded))

# 5. Verify env vars inside a running pod
kubectl exec -n <namespace> deployment/<deployment-name> -- env | findstr "MY_KEY"
```

### CMD

```cmd
:: 1. Check the SealedSecret was accepted by controller
kubectl get sealedsecret <secret-name> -n <namespace>

:: 2. Check the decrypted Secret was created
kubectl get secret <secret-name> -n <namespace>

:: 3. List all keys inside the Secret
kubectl get secret <secret-name> -n <namespace> -o yaml

:: 4. Decode a specific key value (use PowerShell for decoding on Windows)
kubectl get secret <secret-name> -n <namespace> -o jsonpath="{.data.MY_KEY}"

:: 5. Verify env vars inside a running pod
kubectl exec -n <namespace> deployment/<deployment-name> -- env | findstr "MY_KEY"
```

### Linux / macOS

```bash
# 1. Check the SealedSecret was accepted by controller
kubectl get sealedsecret <secret-name> -n <namespace>

# 2. Check the decrypted Secret was created
kubectl get secret <secret-name> -n <namespace>

# 3. List all keys inside the Secret
kubectl get secret <secret-name> -n <namespace> -o yaml

# 4. Decode a specific key value
kubectl get secret <secret-name> -n <namespace> \
  -o jsonpath="{.data.MY_KEY}" | base64 --decode

# 5. Verify env vars inside a running pod
kubectl exec -n <namespace> deployment/<deployment-name> -- env | grep "MY_KEY"
```

---

## Troubleshooting

| Symptom | Cause | Fix |
| :--- | :--- | :--- |
| Output file is empty after kubeseal | Input YAML is UTF-16 LE (PowerShell `>` redirect) | Use `\| Set-Content -Encoding utf8` instead of `>` |
| Env var is empty in pod | SealedSecret was sealed with an empty value | Re-seal with correct value |
| `SealedSecret` stuck in `Pending` | Controller not running | `kubectl get pods -n kube-system` — check controller |
| `cannot decrypt` error | Secret sealed for wrong namespace | Re-seal specifying correct `--namespace` |
| `kubeseal: no such host` | `kubectl` not connected to cluster | Check `kubectl config current-context` |
| `services "sealed-secrets" not found` | Wrong `--controller-name` flag | Use `--controller-name sealed-secrets-controller` |
| Secret exists but pod doesn't pick it up | Deployment not referencing the secret | Add `secretRef` in `envFrom` and rollout restart |

**Force pod to reload after fixing the secret:**

**PowerShell / CMD**
```powershell
kubectl rollout restart deployment/<deployment-name> -n <namespace>
```

**Linux / macOS**
```bash
kubectl rollout restart deployment/<deployment-name> -n <namespace>
```

---

## Gitignore Safety Net

Add this to the root `.gitignore` to prevent accidental plaintext commits:

```gitignore
# Plaintext Kubernetes secrets — never commit
temp-secret.yaml
temp-secret-*.yaml
*-plaintext.yaml
```
