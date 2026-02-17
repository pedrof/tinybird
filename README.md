# Tinybird Analytics for Ghost

[![Gitea Actions](https://git.shadyknollcave.io/micro/tinybird/actions/workflows/build-and-push.yaml/badge.svg)](https://git.shadyknollcave.io/micro/tinybird/actions)

Self-hosted Tinybird analytics deployment for Ghost blog integration.

## Architecture

```
Ghost Blog → Traffic Analytics Service → Tinybird Local → ClickHouse
```

- **Tinybird Local**: Self-contained analytics engine with embedded ClickHouse
- **Traffic Analytics Service**: Ghost's official proxy that enriches analytics data
- **Ghost Integration**: Native analytics via `ghost-stats.js`

## Components

- `tinybird-local`: Analytics engine (port 7181)
- `traffic-analytics`: Event proxy (port 3000)
- Persistent volumes for ClickHouse data

## Prerequisites

1. Ghost 6.0+ deployed in cluster
2. Domain for Tinybird API access
3. Ingress configured (Cilium or nginx-local)

## Deployment

```bash
# Create namespace
kubectl create namespace analytics

# Deploy with Kustomize
kubectl apply -k k8s/overlays/prod

# Verify deployment
kubectl get pods -n analytics
kubectl get ingress -n analytics
```

## Ghost Configuration

Add to your Ghost deployment's environment variables:

```yaml
env:
  - name: ANALYTICS_ENABLED
    value: "true"
  - name: ANALYTICS_PROXY_TARGET
    value: "http://traffic-analytics.analytics.svc.cluster.local:3000"
```

## Accessing Analytics

- Tinybird API: `https://tinybird.shadyknollcave.io`
- Analytics appear in Ghost Admin → Analytics

## Data Persistence

- ClickHouse data: PVC `tinybird-data` (10Gi)
- Redis data: PVC `redis-data` (1Gi)

## Monitoring

```bash
# Check Tinybird logs
kubectl logs -n analytics -l app=tinybird -f

# Check proxy logs
kubectl logs -n analytics -l app=traffic-analytics -f

# Test API
curl https://tinybird.shadyknollcave.io/v0/
```

## References

- [Ghost + Tinybird Integration](https://www.tinybird.co/blog/tinybird-is-the-analytics-platform-for-ghost-6-0)
- [Traffic Analytics Service](https://github.com/TryGhost/TrafficAnalytics)
- [Tinybird Local Docs](https://www.tinybird.co/docs/forward/install-tinybird/local)
