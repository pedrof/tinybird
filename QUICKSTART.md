# Tinybird Analytics - Quick Start Guide

Deploy self-hosted Tinybird analytics for your Ghost blog in minutes.

## What This Does

Deploys a complete analytics stack on your K3s homelab:

- **Tinybird Local**: Real-time analytics engine powered by ClickHouse
- **Traffic Analytics Service**: Privacy-first event proxy for Ghost
- **Automatic TLS**: Let's Encrypt certificates via cert-manager
- **GitOps Ready**: ArgoCD integration for automated deployments

## Prerequisites

✅ K3s cluster running with:
- Cilium CNI (ingress controller)
- cert-manager (TLS certificates)
- ArgoCD (optional, for GitOps)

✅ DNS records pointing to your cluster:
- `tinybird.shadyknollcave.io` → LoadBalancer IP
- `analytics-proxy.shadyknollcave.io` → LoadBalancer IP

✅ Ghost 6.0+ blog (for analytics integration)

## 5-Minute Deployment

### Option 1: Direct Deployment (Quick)

```bash
# 1. Validate manifests
make validate

# 2. Deploy
make deploy

# 3. Check status
make status

# 4. Wait for certificates (1-2 minutes)
kubectl get certificate -n analytics -w

# 5. Test endpoints
make test
```

### Option 2: GitOps with ArgoCD (Recommended)

```bash
# 1. Setup git remotes and push code
./scripts/setup-remotes.sh

# 2. Deploy ArgoCD application
make argocd-deploy

# 3. Watch ArgoCD sync
argocd app get tinybird-analytics --watch

# 4. Verify deployment
make status
```

## Verify Installation

### Check Pods

```bash
kubectl get pods -n analytics
```

Expected output:
```
NAME                                READY   STATUS    RESTARTS   AGE
tinybird-xxxxxxxxx-xxxxx            1/1     Running   0          2m
traffic-analytics-xxxxxxxxx-xxxxx   1/1     Running   0          2m
traffic-analytics-xxxxxxxxx-xxxxx   1/1     Running   0          2m
```

### Check Certificates

```bash
kubectl get certificate -n analytics
```

Expected output:
```
NAME                    READY   SECRET                  AGE
tinybird-tls            True    tinybird-tls            5m
traffic-analytics-tls   True    traffic-analytics-tls   5m
```

### Test API Endpoints

```bash
# Tinybird API
curl https://tinybird.shadyknollcave.io/v0/

# Traffic Analytics health
curl https://analytics-proxy.shadyknollcave.io/health
```

## Connect Your Ghost Blog

### For K8s-deployed Ghost

Edit your Ghost deployment:

```yaml
env:
  - name: ANALYTICS_ENABLED
    value: "true"
  - name: ANALYTICS_PROXY_TARGET
    value: "http://traffic-analytics.analytics.svc.cluster.local:3000"
```

Apply changes:

```bash
kubectl apply -f ghost-deployment.yaml
kubectl rollout restart deployment/ghost -n <ghost-namespace>
```

### For Ghost-CLI Deployment

Edit `config.production.json`:

```json
{
  "analytics": {
    "enabled": true,
    "proxyTarget": "https://analytics-proxy.shadyknollcave.io"
  }
}
```

Restart Ghost:

```bash
ghost restart
```

### Verify Integration

```bash
# Check Ghost logs for analytics events
kubectl logs -n <ghost-namespace> -l app=ghost | grep analytics

# Watch analytics events being processed
make logs-proxy
```

Visit your Ghost blog, then check Ghost Admin → **Analytics** tab.

## Troubleshooting

### Pods Not Starting

```bash
# Check events
kubectl describe pod -n analytics <pod-name>

# Check resource availability
kubectl top nodes
```

**Common issues:**
- Insufficient memory (Tinybird needs 4-8Gi)
- PVC not bound (check storage class)

### Certificates Not Issuing

```bash
# Check certificate status
kubectl describe certificate -n analytics tinybird-tls

# Check cert-manager logs
kubectl logs -n cert-manager -l app=cert-manager -f
```

**Common issues:**
- DNS not propagating (wait 5-10 minutes)
- Let's Encrypt rate limits (use staging issuer)
- HTTP-01 challenge blocked by firewall

### No Analytics Data in Ghost

```bash
# Test the full chain
./scripts/test-integration.sh

# Check if events are reaching the proxy
make logs-proxy

# Check if Tinybird is processing events
make logs-tinybird
```

**Common issues:**
- Ghost not configured correctly
- Network policy blocking traffic
- CORS issues (check browser console)

## Next Steps

### 1. Configure Data Retention

Default: ClickHouse stores data indefinitely.

To set 90-day retention:

```bash
kubectl exec -it -n analytics deployment/tinybird -- clickhouse-client
```

```sql
ALTER TABLE analytics_events MODIFY TTL event_date + INTERVAL 90 DAY;
```

### 2. Query Analytics Programmatically

```bash
# Total page views
curl "https://tinybird.shadyknollcave.io/v0/pipes/page_views.json"

# Top posts (last 7 days)
curl "https://tinybird.shadyknollcave.io/v0/pipes/top_posts.json?days=7"
```

### 3. Monitor Resource Usage

```bash
# Pod metrics
kubectl top pods -n analytics

# Persistent volume usage
kubectl exec -n analytics deployment/tinybird -- df -h /var/lib/clickhouse
```

### 4. Backup ClickHouse Data

```bash
# Create backup script
kubectl exec -n analytics deployment/tinybird -- clickhouse-client --query="BACKUP DATABASE default TO Disk('backups', 'backup.zip')"
```

## Useful Commands

```bash
# View all resources
make status

# Tail Tinybird logs
make logs-tinybird

# Tail proxy logs
make logs-proxy

# Test external endpoints
make test

# Check certificate status
make cert-status

# Delete deployment
make delete
```

## Architecture Diagram

```
┌─────────────────────┐
│   Ghost Blog        │
│  (Your Namespace)   │
└──────────┬──────────┘
           │ HTTP POST /api/v1/page_hit
           │
           ▼
┌─────────────────────────────┐
│  Traffic Analytics Service  │
│  (analytics namespace)      │
│  - Enriches events          │
│  - Privacy-preserving       │
└──────────┬──────────────────┘
           │
           ▼
┌─────────────────────┐
│  Tinybird Local     │
│  - ClickHouse DB    │
│  - Redis Cache      │
│  - Analytics API    │
└─────────────────────┘
           │
           ▼
    ┌──────────┐
    │  Ghost   │
    │  Admin   │ ← Query analytics
    │  Panel   │
    └──────────┘
```

## Performance Expectations

**Resource Usage:**
- Tinybird: ~4-6Gi RAM, 1-2 CPU cores
- Proxy: ~256-512Mi RAM, 0.1-0.5 CPU cores
- Storage: ~1Gi per 100K page views/month

**Latency:**
- Event ingestion: <50ms
- Analytics queries: <200ms (p95)
- Dashboard load: <1s

**Scalability:**
- Supports up to ~10M page views/month on a single instance
- For larger scale, consider Tinybird Cloud

## Support & Resources

- **Documentation**: See `GHOST_INTEGRATION.md`
- **Testing**: Run `./scripts/test-integration.sh`
- **Logs**: Use `make logs-tinybird` and `make logs-proxy`

## License & Privacy

- Tinybird Local: Apache 2.0
- Traffic Analytics: MIT
- **Privacy**: Cookie-free, GDPR-compliant, no personal data stored

---

**Happy analyzing! 📊**
