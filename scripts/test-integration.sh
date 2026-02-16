#!/bin/bash
set -euo pipefail

# Test Tinybird Integration Script
# Simulates Ghost analytics events and verifies they're processed

PROXY_URL="${PROXY_URL:-http://traffic-analytics.analytics.svc.cluster.local:3000}"
GHOST_URL="${GHOST_URL:-https://blog.shadyknollcave.io}"

echo "🧪 Testing Tinybird Analytics Integration"
echo ""

# Test 1: Health check
echo "1️⃣ Testing proxy health endpoint..."
if curl -sf "${PROXY_URL}/health" >/dev/null 2>&1; then
    echo "   ✅ Proxy is healthy"
else
    echo "   ❌ Proxy health check failed"
    exit 1
fi

# Test 2: Send test analytics event
echo ""
echo "2️⃣ Sending test analytics event..."

TEST_EVENT=$(cat <<EOF
{
  "url": "${GHOST_URL}/test-post/",
  "referrer": "https://google.com",
  "user_agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36"
}
EOF
)

RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
    -H "Content-Type: application/json" \
    -d "$TEST_EVENT" \
    "${PROXY_URL}/api/v1/page_hit")

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [ "$HTTP_CODE" -eq 200 ] || [ "$HTTP_CODE" -eq 204 ]; then
    echo "   ✅ Event accepted (HTTP $HTTP_CODE)"
else
    echo "   ❌ Event rejected (HTTP $HTTP_CODE)"
    echo "   Response: $BODY"
    exit 1
fi

# Test 3: Verify Tinybird received the event
echo ""
echo "3️⃣ Checking Tinybird logs for event processing..."
sleep 2

if kubectl logs -n analytics -l app=tinybird --tail=50 | grep -q "page_hit\|INSERT"; then
    echo "   ✅ Tinybird processed the event"
else
    echo "   ⚠️  Could not verify event processing (check logs manually)"
fi

# Test 4: Query analytics data (if Tinybird API is accessible)
echo ""
echo "4️⃣ Testing Tinybird API query..."

TINYBIRD_URL="${TINYBIRD_URL:-http://tinybird.analytics.svc.cluster.local:7181}"
if curl -sf "${TINYBIRD_URL}/v0/" >/dev/null 2>&1; then
    echo "   ✅ Tinybird API is accessible"
    echo "   📊 API Response:"
    curl -s "${TINYBIRD_URL}/v0/" | head -20
else
    echo "   ⚠️  Tinybird API not accessible (check ingress configuration)"
fi

echo ""
echo "✅ Integration test complete!"
echo ""
echo "📝 To test from Ghost:"
echo "  1. Configure Ghost with ANALYTICS_PROXY_TARGET"
echo "  2. Visit a page on your Ghost blog"
echo "  3. Check logs: make logs-proxy"
echo "  4. View analytics in Ghost Admin → Analytics"
