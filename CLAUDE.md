# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Self-hosted Tinybird analytics platform for Ghost blog integration, deployed on K3s homelab.

**Architecture Flow:**
```
Ghost Blog → Traffic Analytics Service → Tinybird Local → ClickHouse
```

**Components:**
- **Tinybird Local** (`tinybirdco/tinybird-local:latest`): Analytics engine with embedded ClickHouse (port 7181)
- **Traffic Analytics Service** (`ghost/traffic-analytics:latest`): Privacy-first event proxy (port 3000)
- **Storage**: PVCs for ClickHouse (10Gi) and Redis (1Gi)
- **Ingress**: Cilium with Let's Encrypt TLS

## Development Environment

### Homelab Infrastructure
- **K3s cluster**: 3x Beelink SER9 Max nodes
- **Network**: VLAN 10.10.10.0/24
- **CNI**: Cilium v1.18.6 (BGP, kube-proxy replacement)
- **Ingress**: `cilium` (public 10.10.10.200) and `nginx-local` (internal 10.10.10.210)
- **cert-manager**: v1.19.2 for TLS certificates
- **ArgoCD**: GitOps deployments
- **Container tool**: podman (NOT docker)

### Git Workflow
- **Primary remote**: `origin` → https://git.shadyknollcave.io/micro/tinybird (Gitea, HTTPS)
- **Backup remote**: `github` → git@github.com:pedrof/tinybird (GitHub, SSH)
- **Push to both**: `git push origin main && git push github main`
- **CLI tools**: `tea` for Gitea, `gh` for GitHub

## Key Commands

### Deployment
```bash
make validate         # Validate K8s manifests
make deploy          # Deploy to cluster (Kustomize)
make status          # Check all resources
make delete          # Delete deployment

make argocd-deploy   # Deploy ArgoCD app
make argocd-delete   # Delete ArgoCD app
```

### Monitoring
```bash
make logs-tinybird   # Tail Tinybird logs
make logs-proxy      # Tail Traffic Analytics logs
make test            # Test external endpoints
make cert-status     # Check TLS certificates
```

### Testing Scripts
```bash
./scripts/init-tinybird.sh          # Full deployment automation
./scripts/test-integration.sh       # Test Ghost → Tinybird flow
./scripts/diagnose-actions.sh       # Debug Gitea Actions
```

## Kubernetes Architecture

### Namespace: `analytics`

**Deployments:**
- `tinybird`: 1 replica (Recreate strategy for stateful workload)
  - Resources: 4-8Gi RAM, 1-2 CPU cores
  - Volumes: `/var/lib/clickhouse`, `/redis-data`
  - Liveness/Readiness: `GET /v0/` on port 7181

- `traffic-analytics`: 2 replicas
  - Resources: 256-512Mi RAM, 0.1-0.5 CPU
  - Health check: `GET /health` on port 3000

**Services:**
- `tinybird`: ClusterIP on port 7181
- `traffic-analytics`: ClusterIP on port 3000

**Ingress:**
- `tinybird.shadyknollcave.io` → tinybird:7181 (Cilium, TLS)
- `analytics-proxy.shadyknollcave.io` → traffic-analytics:3000 (Cilium, TLS)

**Kustomize Structure:**
- `k8s/base/`: Base manifests
- `k8s/overlays/prod/`: Production overlay with resource limits

## CI/CD Pipeline (Gitea Actions)

### Workflows (`.gitea/workflows/`)

**build-and-push.yaml** - Main CI/CD pipeline
- **Triggers**: Push to main/develop, tags, PRs, manual dispatch
- **Steps**:
  1. Builds Traffic Analytics from source (GitHub clone)
  2. Mirrors Tinybird Local from upstream registry
  3. Uses **podman** for all builds (not docker)
  4. Pushes to `git.shadyknollcave.io/micro/*` registry
  5. Auto-updates Kustomize image tags in `k8s/overlays/prod/kustomization.yaml`
  6. Commits manifest changes to git

**mirror-images.yaml** - Weekly upstream sync
- **Triggers**: Cron (Sundays 2 AM), manual
- **Purpose**: Ensures availability even if upstream is down

**validate.yaml** - Manifest validation
- **Triggers**: PRs, pushes to `k8s/**`
- **Checks**: YAML syntax, Kustomize builds, dry-run applies

### Image Tags
```
git.shadyknollcave.io/micro/traffic-analytics:latest           # main branch
git.shadyknollcave.io/micro/traffic-analytics:main-a1b2c3d     # branch + SHA
git.shadyknollcave.io/micro/traffic-analytics:v1.0.0           # semver tag
git.shadyknollcave.io/micro/tinybird-local:latest              # mirrored
git.shadyknollcave.io/micro/tinybird-local:20260216            # date-tagged
```

### Required Secret
- **Name**: `GIT_TOKEN` (NOT `GITEA_TOKEN`)
- **Scope**: `write:package`
- **Location**: Repository secrets at `git.shadyknollcave.io/micro/tinybird/settings/secrets`

### Troubleshooting Actions
If workflows don't trigger:
1. Check Actions tab exists: `git.shadyknollcave.io/micro/tinybird/actions`
2. Verify runner is registered and active: `/settings/actions/runners`
3. Run diagnostic: `./scripts/diagnose-actions.sh`
4. Check Gitea config has `[actions] ENABLED = true`

## Ghost Integration

### Configuration
Ghost requires two environment variables:

```yaml
env:
  - name: ANALYTICS_ENABLED
    value: "true"
  - name: ANALYTICS_PROXY_TARGET
    value: "http://traffic-analytics.analytics.svc.cluster.local:3000"
```

### Event Flow
1. User visits Ghost blog
2. `ghost-stats.js` sends POST to Traffic Analytics `/api/v1/page_hit`
3. Service enriches event (user agent, referrer, privacy-preserving signatures)
4. Proxies to Tinybird Local `/v0/events`
5. Stored in ClickHouse
6. Queried via Ghost Admin → Analytics tab

### Verification
```bash
# Check Ghost logs
kubectl logs -n <ghost-namespace> -l app=ghost | grep analytics

# Watch events
make logs-proxy

# Test integration
./scripts/test-integration.sh
```

## Data Management

### ClickHouse Access
```bash
kubectl exec -it -n analytics deployment/tinybird -- clickhouse-client
```

### Set Data Retention (90 days)
```sql
ALTER TABLE analytics_events MODIFY TTL event_date + INTERVAL 90 DAY;
```

### Query APIs
```bash
curl "https://tinybird.shadyknollcave.io/v0/pipes/page_views.json"
curl "https://tinybird.shadyknollcave.io/v0/pipes/top_posts.json?days=7"
```

## Important Notes

### Container Tools
- **Use podman**, not docker (per homelab setup)
- CI/CD workflows use podman for builds
- Images target `linux/amd64` platform

### Network
- **Internal**: Services communicate via ClusterIP (traffic-analytics.analytics.svc.cluster.local)
- **External**: For Ghost outside cluster, use `https://analytics-proxy.shadyknollcave.io`

### Resource Requirements
- **Tinybird**: 4-8Gi RAM minimum (ClickHouse)
- **Expected scale**: ~10M page views/month on single instance
- **Storage growth**: ~1Gi per 100K page views/month

### Privacy & Compliance
- Cookie-free tracking
- IP addresses hashed with daily rotating salts
- No personal data stored
- GDPR compliant by default

## ArgoCD Integration

**Application**: `tinybird-analytics`
- **Repo**: https://git.shadyknollcave.io/micro/tinybird.git
- **Path**: `k8s/overlays/prod`
- **Namespace**: `analytics`
- **Sync**: Automated (prune, self-heal)

After CI/CD updates image tags:
1. ArgoCD detects git commit
2. Auto-syncs new images
3. K8s pulls from Gitea registry

## Common Issues

### Workflows not triggering
- Verify `GIT_TOKEN` secret exists (not `GITEA_TOKEN`)
- Check runner is active at `/settings/actions/runners`
- Manually trigger via Actions tab → "Run workflow"

### Pods not starting
- Check memory availability (Tinybird needs 4-8Gi)
- Verify PVCs are bound: `kubectl get pvc -n analytics`

### No analytics in Ghost
- Verify Ghost config has correct `ANALYTICS_PROXY_TARGET`
- Check network policies allow traffic
- Test: `./scripts/test-integration.sh`

### Certificates not issuing
- DNS must resolve to LoadBalancer IP
- Check cert-manager logs
- Let's Encrypt rate limits (use staging issuer for testing)
