


For ArgoCD password:

kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | % { [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($_)) }


For NGINX Ingress Controller password:

kubectl -n ingress-nginx get secret ingress-nginx-controller -o jsonpath="{.data.controller-ingress-class-secret}" | % { [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($_)) }




1. See Everything in a Namespace (Most Useful)
kubectl get all -n argocd

2. List All Namespaces
kubectl get ns

3. List Pods in a Specific Namespace
kubectl get pods -n argocd

4. List Services in a Namespace
kubectl get svc -n argocd

5. List Deployments in a Namespace
kubectl get deployments -n argocd

6. List Ingresses in a Namespace
kubectl get ingress -n argocd

7. List ConfigMaps in a Namespace
kubectl get configmaps -n argocd

8. List Secrets in a Namespace
kubectl get secrets -n argocd

9. List PersistentVolumeClaims in a Namespace
kubectl get pvc -n argocd

10. List Nodes
kubectl get nodes

11. Get Detailed Info About a Specific Pod
kubectl get pod <pod-name> -n argocd -o wide

12. Check Logs of a Pod
kubectl logs <pod-name> -n argocd

13. Follow Logs in Real-Time
kubectl logs -f <pod-name> -n argocd

14. Get Events in a Namespace
kubectl get events -n argocd

15. Describe a Resource for Troubleshooting
kubectl describe pod <pod-name> -n argocd
kubectl describe svc <service-name> -n argocd
kubectl describe ingress <ingress-name> -n argocd

16. Exec into a Running Pod (Get a Shell)
kubectl exec -it <pod-name> -n argocd -- /bin/bash

17. List All Resources of a Specific Type
kubectl get pods --all-namespaces
kubectl get services --all-namespaces
kubectl get deployments --all-namespaces
kubectl get ingress --all-namespaces

18. Check Resource Usage (CPU/Memory)
kubectl top pod -n argocd
kubectl top node

19. List All Namespaces with Resource Usage
kubectl get pods --all-namespaces -o custom-columns=NAMESPACE:.metadata.namespace,POD:.metadata.name,CPU:.spec.containers[0].resources.requests.cpu,MEMORY:.spec.containers[0].resources.requests.memory

20. List All Resources of All Types in All Namespaces
kubectl get all --all-namespaces





 kubectl exec -n identity deployment/identity-backend -- python3 -c "import json; d=json.load(open('/app/keys/keys.json')); print('active_kid:', d['active_kid']); print('stored kids:', list(d['keys'].keys()))"


# ─── LOGGING COMMANDS ───────────────────────────────────────────────────────

## View logs (last N lines)
kubectl logs -l app=identity-backend  -n identity  --tail=50
kubectl logs -l app=workspace-backend -n workspace --tail=50
kubectl logs -l app=workspace-web     -n workspace --tail=50

## Follow logs in real-time (Ctrl+C to stop)
kubectl logs -l app=identity-backend  -n identity  -f
kubectl logs -l app=workspace-backend -n workspace -f

## Logs from last N minutes
kubectl logs -l app=identity-backend  -n identity  --since=5m
kubectl logs -l app=workspace-backend -n workspace --since=5m

## Logs from a specific pod (not label selector)
kubectl get pods -n identity                          # get pod name
kubectl logs <pod-name> -n identity --tail=50

## Check logs at startup only (useful for key_manager ✅/⚠️ messages)
kubectl logs -l app=identity-backend -n identity --tail=100 | findstr "key_manager\|RSA\|kid"

## Previous crashed container logs
kubectl logs <pod-name> -n identity --previous

# ─── RSA KEY CHECKS ─────────────────────────────────────────────────────────

## Check keys.json exists on PVC
kubectl exec -n identity deployment/identity-backend -- ls -la /app/keys/

## Show active_kid in keys.json
kubectl exec -n identity deployment/identity-backend -- python3 -c "import json; d=json.load(open('/app/keys/keys.json')); print('active_kid:', d['active_kid']); print('stored kids:', list(d['keys'].keys()))"

## Check JWKS endpoint kid (must match active_kid above)
kubectl exec -n identity deployment/identity-backend -- python3 -c "import urllib.request,json; r=urllib.request.urlopen('http://localhost:8000/.well-known/jwks.json'); [print('jwks kid:',k['kid']) for k in json.loads(r.read())['keys']]"

# ─── TERMINAL ACCESS (exec into pod) ────────────────────────────────────────

## Get a shell inside a running pod  (use /bin/sh — alpine images have no bash)
kubectl exec -it -n identity  deployment/identity-backend  -- /bin/sh
kubectl exec -it -n workspace deployment/workspace-backend -- /bin/sh
kubectl exec -it -n workspace deployment/workspace-web     -- /bin/sh

## Useful commands once inside:
# cat /app/keys/keys.json          → check RSA keys
# env | grep VITE_                 → check ConfigMap env vars (web pod)
# env                              → all env vars
# cat /etc/nginx/conf.d/*.conf     → nginx config (web pod)
# exit                             → leave the shell








kubectl exec -n workspace deployment/workspace-backend -- env | findstr "OAUTH_CLIENT"