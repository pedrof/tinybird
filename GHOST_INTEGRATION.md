# Ghost Integration Guide

This guide explains how to connect your Ghost blog to the self-hosted Tinybird analytics platform.

## Prerequisites

- Ghost 6.0 or higher
- Ghost deployed in the same K8s cluster (or accessible network)
- Tinybird analytics deployed and running

## Architecture

```
┌─────────────┐         ┌──────────────────┐         ┌──────────────┐
│             │  POST   │ Traffic          │  POST   │              │
│ Ghost Blog  ├────────▶│ Analytics        ├────────▶│  Tinybird    │
│             │         │ Service (Proxy)  │         │  Local       │
└─────────────┘         └──────────────────┘         └──────────────┘
                                                             │
                                                             ▼
                                                      ┌──────────────┐
                                                      │  ClickHouse  │
                                                      │  Database    │
                                                      └──────────────┘
```

## Step 1: Enable Analytics in Ghost

If Ghost is deployed via Helm or custom manifests, add these environment variables:

```yaml
env:
  - name: ANALYTICS_ENABLED
    value: "true"
  - name: ANALYTICS_PROXY_TARGET
    value: "http://traffic-analytics.analytics.svc.cluster.local:3000"
```

If using Ghost's `config.production.json`:

```json
{
  "analytics": {
    "enabled": true,
    "proxyTarget": "http://traffic-analytics.analytics.svc.cluster.local:3000"
  }
}
```

## Step 2: Restart Ghost

```bash
# If using K8s deployment
kubectl rollout restart deployment/ghost -n <ghost-namespace>

# If using Ghost-CLI
ghost restart
```

## Step 3: Verify Integration

### Check Ghost Logs

```bash
kubectl logs -n <ghost-namespace> -l app=ghost | grep analytics
```

You should see:
```
Analytics enabled, events will be sent to http://traffic-analytics.analytics.svc.cluster.local:3000
```

### Check Traffic Analytics Logs

```bash
make logs-proxy
# or
kubectl logs -n analytics -l app=traffic-analytics -f
```

You should see incoming POST requests:
```
POST /api/v1/page_hit
200 - Analytics event processed
```

### Test Page Views

1. Visit your Ghost blog in a browser
2. Navigate to a few posts
3. Check the proxy logs for incoming events

## Step 4: Access Analytics in Ghost Admin

1. Log into Ghost Admin: `https://yourblog.com/ghost`
2. Navigate to **Analytics** in the sidebar
3. You should see:
   - Page views
   - Top posts
   - Traffic sources
   - Geographic data

## Troubleshooting

### No analytics data appearing

**Check 1: Verify services are running**
```bash
make status
```

**Check 2: Test proxy connectivity from Ghost pod**
```bash
# Get Ghost pod name
kubectl get pods -n <ghost-namespace> -l app=ghost

# Exec into pod and test
kubectl exec -it <ghost-pod-name> -n <ghost-namespace> -- sh
wget -O- http://traffic-analytics.analytics.svc.cluster.local:3000/health
```

**Check 3: Verify Tinybird is receiving events**
```bash
make logs-tinybird
```

**Check 4: Check network policies**
```bash
kubectl get networkpolicies -n analytics
kubectl get networkpolicies -n <ghost-namespace>
```

### Analytics showing but data is incomplete

**Check browser console for errors:**
1. Open browser DevTools (F12)
2. Visit your Ghost blog
3. Look for failed requests to `/api/v1/page_hit`

**Verify CORS settings:**
The Traffic Analytics Service should automatically handle CORS, but verify Ghost's URL is allowed.

### "Analytics service unavailable" error

**Check service DNS resolution:**
```bash
kubectl run -it --rm debug --image=busybox --restart=Never -- sh
nslookup traffic-analytics.analytics.svc.cluster.local
```

**Verify service endpoints:**
```bash
kubectl get endpoints -n analytics traffic-analytics
```

## Advanced Configuration

### Custom Analytics Proxy URL (External Access)

If Ghost is running outside the cluster:

```yaml
env:
  - name: ANALYTICS_PROXY_TARGET
    value: "https://analytics-proxy.shadyknollcave.io"
```

**Note:** Ensure ingress is configured and accessible.

### Rate Limiting

The Traffic Analytics Service includes built-in rate limiting. To adjust:

1. Create a ConfigMap with custom settings
2. Mount as environment variables in the deployment

### Data Retention

Tinybird Local stores data in ClickHouse. To configure retention:

1. Access ClickHouse console:
   ```bash
   kubectl exec -it -n analytics deployment/tinybird -- clickhouse-client
   ```

2. Set TTL (Time To Live):
   ```sql
   ALTER TABLE analytics_events MODIFY TTL event_date + INTERVAL 90 DAY;
   ```

## Ghost Admin Analytics Features

Once integrated, Ghost Admin provides:

- **Dashboard Overview**: Total views, members, newsletter stats
- **Posts Analytics**: Views per post, engagement metrics
- **Audience Insights**: Geographic distribution, referral sources
- **Real-time Data**: Live visitor count and recent page views
- **Custom Date Ranges**: Filter analytics by time period

## API Access

Query Tinybird directly via API:

```bash
# Get total page views
curl "https://tinybird.shadyknollcave.io/v0/pipes/analytics_page_views.json"

# Get top posts
curl "https://tinybird.shadyknollcave.io/v0/pipes/analytics_top_posts.json?date_from=2026-01-01"
```

## Privacy & GDPR Compliance

Tinybird analytics is cookie-free and privacy-first:

- No personal data stored
- IP addresses hashed with daily rotating salts
- No cross-site tracking
- GDPR compliant by default

## Resources

- [Ghost Analytics Documentation](https://ghost.org/docs/analytics/)
- [Tinybird + Ghost Integration](https://www.tinybird.co/blog/tinybird-is-the-analytics-platform-for-ghost-6-0)
- [Traffic Analytics Service GitHub](https://github.com/TryGhost/TrafficAnalytics)
