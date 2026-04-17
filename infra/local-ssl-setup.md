# Local SSL Setup (mkcert)

This document explains how local HTTPS (SSL) is configured for `*.local` domains on the SaaS platform during local development.

## Why Do We Need SSL Locally?
Many modern web features (like `window.crypto.subtle` used in OAuth PKCE flows, Service Workers, or Secure Cookies) are **strictly blocked by modern browsers** if the connection is not secure (served over `http://` instead of `https://`).

To solve this without manually bypassing browser warnings, we use `mkcert` to generate a locally trusted Certificate Authority (CA) and wildcard SSL certificate.

---

## 1. Prerequisites (Installing `mkcert`)
`mkcert` is a simple tool for making locally-trusted development certificates. 

1. Download the executable:
   ```powershell
   Invoke-WebRequest -Uri "https://dl.filippo.io/mkcert/latest?for=windows/amd64" -OutFile mkcert.exe
   ```
2. Install the local CA into your Windows System Trust Store (this removes the "Not Secure" browser warning forever):
   ```powershell
   .\mkcert.exe -install
   ```
   *(Windows will prompt you with a Security Warning. Click **Yes**).*

---

## 2. Generating the Certificate
We generate a wildcard certificate for all our local services (e.g., `workspace.local`, `grafana.local`).
```powershell
.\mkcert.exe "*.local"
```
This generates two files in your directory:
- `_wildcard.local.pem` (The public certificate)
- `_wildcard.local-key.pem` (The private key)

---

## 3. Applying the Certificate to Kubernetes (GitOps)
Because this project uses GitOps (ArgoCD) to manage infrastructure, we **cannot** simply commit the private key to GitHub. Instead, we bundle the certificate into a Kubernetes Secret, encrypt it using `kubeseal`, and commit the encrypted file.

### Step 3A: Create a dry-run Secret
First, we format the certificate into a Kubernetes TLS Secret YAML file without applying it to the cluster directly:
```powershell
kubectl create secret tls local-wildcard-tls --cert=_wildcard.local.pem --key=_wildcard.local-key.pem -n ingress-nginx --dry-run=client -o yaml > local-tls-secret.yaml
```

### Step 3B: Encrypt the Secret (SealedSecret)
We encrypt the raw secret using `kubeseal` so that it is safe to commit to version control. Only our local Kubernetes cluster controller has the decryption key:
```powershell
kubeseal --format yaml < local-tls-secret.yaml > infra/gitops/infra/ingress-nginx-tls-sealed.yaml
```
*(After this, safely delete `_wildcard.local.pem`, `_wildcard.local-key.pem`, and `local-tls-secret.yaml`)*

### Step 3C: Register in Kustomize
Open `infra/gitops/infra/kustomization.yaml` and add the sealed file to the resources list so ArgoCD deploys it:
```yaml
resources:
  # ...
  - ingress-nginx-tls-sealed.yaml
```

---

## 4. Configuring NGINX Ingress Controller
Finally, we configure the Kubernetes NGINX Ingress Controller to use this certificate as its global default for all incoming HTTPS traffic.

In `infra/gitops/argocd/nginx-ingress.yaml`, add the `default-ssl-certificate` argument to the controller:
```yaml
      values: |
        controller:
          extraArgs:
            default-ssl-certificate: "ingress-nginx/local-wildcard-tls"
```

Because ArgoCD synchronizes this Helm values file, the NGINX controller automatically detects the TLS secret we created in Step 3 and uses it.

## Result
Any service exposed via a standard `Ingress` routing to a `*.local` host will automatically be served over valid, trusted HTTPS!
