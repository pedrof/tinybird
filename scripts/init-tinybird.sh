#!/bin/bash
set -euo pipefail

# Tinybird Analytics Initialization Script
# This script deploys Tinybird and verifies the installation

NAMESPACE="analytics"
TIMEOUT=300

echo "🚀 Deploying Tinybird Analytics Platform..."
echo ""

# Check prerequisites
echo "📋 Checking prerequisites..."
command -v kubectl >/dev/null 2>&1 || { echo "❌ kubectl not found"; exit 1; }
command -v kustomize >/dev/null 2>&1 || { echo "⚠️  kustomize not found, using kubectl kustomize"; }

# Validate manifests
echo "✅ Validating manifests..."
kubectl kustomize k8s/overlays/prod >/dev/null || { echo "❌ Manifest validation failed"; exit 1; }

# Deploy
echo "📦 Deploying resources..."
kubectl apply -k k8s/overlays/prod

# Wait for namespace
echo "⏳ Waiting for namespace..."
kubectl wait --for=jsonpath='{.status.phase}'=Active namespace/$NAMESPACE --timeout=30s

# Wait for PVCs
echo "💾 Waiting for PVCs to be bound..."
kubectl wait --for=jsonpath='{.status.phase}'=Bound pvc/tinybird-data -n $NAMESPACE --timeout=60s || true
kubectl wait --for=jsonpath='{.status.phase}'=Bound pvc/redis-data -n $NAMESPACE --timeout=60s || true

# Wait for Tinybird deployment
echo "🐦 Waiting for Tinybird deployment..."
kubectl rollout status deployment/tinybird -n $NAMESPACE --timeout=${TIMEOUT}s

# Wait for Traffic Analytics deployment
echo "📊 Waiting for Traffic Analytics deployment..."
kubectl rollout status deployment/traffic-analytics -n $NAMESPACE --timeout=${TIMEOUT}s

# Check pod status
echo ""
echo "📦 Pod Status:"
kubectl get pods -n $NAMESPACE

echo ""
echo "🌐 Service Status:"
kubectl get svc -n $NAMESPACE

echo ""
echo "🔒 Ingress Status:"
kubectl get ingress -n $NAMESPACE

echo ""
echo "📜 Certificate Status:"
kubectl get certificate -n $NAMESPACE 2>/dev/null || echo "⚠️  Certificates not ready yet (this is normal)"

# Test endpoints
echo ""
echo "🧪 Testing endpoints..."

# Test Tinybird service (internal)
if kubectl run test-tinybird --rm -i --restart=Never --image=curlimages/curl:latest -- \
   curl -s http://tinybird.analytics.svc.cluster.local:7181/v0/ >/dev/null 2>&1; then
    echo "✅ Tinybird service is responding"
else
    echo "⚠️  Tinybird service not yet ready"
fi

# Test Traffic Analytics service (internal)
if kubectl run test-proxy --rm -i --restart=Never --image=curlimages/curl:latest -- \
   curl -s http://traffic-analytics.analytics.svc.cluster.local:3000/health >/dev/null 2>&1; then
    echo "✅ Traffic Analytics service is responding"
else
    echo "⚠️  Traffic Analytics service not yet ready"
fi

echo ""
echo "✨ Deployment complete!"
echo ""
echo "📝 Next steps:"
echo "  1. Wait for certificates to be issued (check: kubectl get certificate -n analytics)"
echo "  2. Verify ingress endpoints are accessible:"
echo "     - Tinybird API: https://tinybird.shadyknollcave.io/v0/"
echo "     - Proxy: https://analytics-proxy.shadyknollcave.io/health"
echo "  3. Configure Ghost integration (see GHOST_INTEGRATION.md)"
echo ""
echo "📚 Useful commands:"
echo "  make status           - Check deployment status"
echo "  make logs-tinybird    - View Tinybird logs"
echo "  make logs-proxy       - View proxy logs"
echo "  make test             - Test external endpoints"
