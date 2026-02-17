# CI/CD Pipeline Architecture

## Complete Workflow Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                        GIT TRIGGER                              │
│  • Push to main/develop                                         │
│  • Create PR                                                    │
│  • Push semver tag (v1.0.0)                                    │
│  • Weekly cron (Sunday 2AM)                                    │
│  • Manual dispatch                                             │
└─────────────────────┬───────────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────────┐
│                   GITEA ACTIONS RUNNER                          │
│  • Minimal Ubuntu container (no sudo)                           │
│  • Root access for apt-get                                      │
│  • Internet access                                              │
│  • Workspace: /workspace/                                       │
└─────────────────────┬───────────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────────┐
│               WORKFLOW: validate.yaml                            │
│  1. Install: git, curl, yamllint                                │
│  2. Clone repository                                            │
│  3. Download kubectl                                            │
│  4. Validate k8s base manifests                                 │
│  5. Validate k8s prod overlay                                   │
│  6. Check YAML syntax                                           │
│  7. Validate ArgoCD app                                         │
│  ⏱️  Runtime: ~2-3 minutes                                      │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│          WORKFLOW: build-and-push.yaml (Job 1)                  │
│  1. Install: git, curl, podman                                  │
│  2. Clone tinybird repo                                         │
│  3. Clone TrafficAnalytics from GitHub                          │
│  4. Login to Gitea registry                                     │
│  5. Generate image tags (latest, main, SHA)                     │
│  6. Build with podman (linux/amd64)                             │
│  7. Push all tags to registry                                   │
│  ⏱️  Runtime: ~10-15 minutes                                    │
└─────────────────────┬───────────────────────────────────────────┘
                      │
                      ├──────────────────┐
                      │                  │
                      ▼                  ▼
┌─────────────────────────────┐  ┌─────────────────────────────┐
│  Job 2: mirror-tinybird     │  │  OUTPUT: Registry Images    │
│  1. Install podman          │  │  • traffic-analytics:latest │
│  2. Login to registry       │  │  • traffic-analytics:main   │
│  3. Pull from Docker Hub    │  │  • traffic-analytics:SHA    │
│  4. Tag for local registry  │  └─────────────────────────────┘
│  5. Push (latest + date)    │
│  ⏱️  Runtime: ~3-5 minutes  │
└─────────────────┬───────────┘
                  │
                  │
        ┌─────────┴──────────┐
        │                    │
        ▼                    ▼
┌─────────────────────┐  ┌─────────────────────────────┐
│ Job 3: update-      │  │  OUTPUT: Registry Images    │
│        manifests    │  │  • tinybird-local:latest    │
│  1. Install git     │  │  • tinybird-local:20260216  │
│  2. Configure bot   │  └─────────────────────────────┘
│  3. Clone with auth │
│  4. Update images:  │
│     - tinybird:latest│
│     - analytics:SHA │
│  5. Commit changes  │
│  6. Push to main    │
│  ⏱️  Runtime: ~1min │
└─────────────────┬───┘
                  │
                  ▼
┌─────────────────────────────────────────────────────────────────┐
│               UPDATED KUSTOMIZATION.YAML                        │
│                                                                 │
│  images:                                                        │
│    - name: tinybirdco/tinybird-local                           │
│      newName: git.shadyknollcave.io/micro/tinybird-local       │
│      newTag: latest                                            │
│    - name: ghost/traffic-analytics                             │
│      newName: git.shadyknollcave.io/micro/traffic-analytics    │
│      newTag: main-abc1234                                      │
└─────────────────────┬───────────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────────┐
│                    ARGOCD AUTO-SYNC                             │
│  • Detects manifest change                                      │
│  • Pulls updated kustomization                                  │
│  • Resolves image references                                    │
│  • Applies to K3s cluster                                       │
│  • Monitors health status                                       │
│  ⏱️  Sync time: ~1-2 minutes                                    │
└─────────────────────┬───────────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────────┐
│                  K3S CLUSTER DEPLOYMENT                         │
│  Namespace: tinybird-analytics                                  │
│                                                                 │
│  ┌─────────────────────┐  ┌─────────────────────┐             │
│  │  Tinybird Pods      │  │  Analytics Pods     │             │
│  │  • Pulls from       │  │  • Pulls from       │             │
│  │    local registry   │  │    local registry   │             │
│  │  • Mounts PVC       │  │  • Connects to      │             │
│  │  • Exposes service  │  │    Tinybird API     │             │
│  └─────────────────────┘  └─────────────────────┘             │
│                                                                 │
│  ┌─────────────────────────────────────────┐                   │
│  │            Ingress (Cilium)             │                   │
│  │  analytics.shadyknollcave.io            │                   │
│  │  • LoadBalancer: 10.10.10.200           │                   │
│  │  • TLS: Let's Encrypt                   │                   │
│  └─────────────────────────────────────────┘                   │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│              WORKFLOW: mirror-images.yaml                        │
│  • Scheduled: Every Sunday 2 AM UTC                             │
│  • Matrix Strategy: latest + beta                               │
│  • Pulls from Docker Hub                                        │
│  • Pushes to Gitea registry                                     │
│  • Date-tagged for tracking                                     │
│  ⏱️  Runtime: ~3-5 minutes per variant                          │
└─────────────────────────────────────────────────────────────────┘
