#!/bin/bash
set -euo pipefail

# Gitea Actions Diagnostic Script
# Run this to find out why workflows aren't triggering

GITEA_URL="https://git.shadyknollcave.io"
REPO_OWNER="micro"
REPO_NAME="tinybird"
REPO_URL="${GITEA_URL}/${REPO_OWNER}/${REPO_NAME}"

echo "🔍 Gitea Actions Diagnostic"
echo "Repository: ${REPO_URL}"
echo ""

# Check 1: Workflow files exist
echo "1️⃣ Checking workflow files..."
if [ -d ".gitea/workflows" ]; then
    WORKFLOW_COUNT=$(find .gitea/workflows -name "*.yaml" -o -name "*.yml" | wc -l)
    echo "   ✅ Found ${WORKFLOW_COUNT} workflow file(s)"
    find .gitea/workflows -type f | while read -r file; do
        echo "      - $(basename "$file")"
    done
else
    echo "   ❌ No .gitea/workflows directory found"
    exit 1
fi

# Check 2: Workflows are committed
echo ""
echo "2️⃣ Checking if workflows are committed to git..."
if git ls-files --error-unmatch .gitea/workflows/*.yaml >/dev/null 2>&1; then
    echo "   ✅ Workflows are committed"
else
    echo "   ❌ Workflows are NOT committed to git"
    echo "   Run: git add .gitea && git commit && git push"
    exit 1
fi

# Check 3: Latest commit includes workflows
echo ""
echo "3️⃣ Checking latest commit..."
LATEST_COMMIT=$(git log -1 --oneline)
echo "   Latest: ${LATEST_COMMIT}"

# Check 4: YAML syntax
echo ""
echo "4️⃣ Validating YAML syntax..."
if command -v yamllint >/dev/null 2>&1; then
    if yamllint -d relaxed .gitea/workflows/ 2>/dev/null; then
        echo "   ✅ YAML syntax is valid"
    else
        echo "   ⚠️  YAML syntax warnings (may still work)"
    fi
else
    echo "   ℹ️  yamllint not installed, skipping syntax check"
fi

# Check 5: Actions API endpoint
echo ""
echo "5️⃣ Testing Gitea Actions API..."
API_URL="${GITEA_URL}/api/v1/repos/${REPO_OWNER}/${REPO_NAME}/actions/workflows"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "${API_URL}" 2>/dev/null || echo "000")

if [ "$HTTP_CODE" = "200" ]; then
    echo "   ✅ Actions API is accessible (HTTP 200)"
elif [ "$HTTP_CODE" = "404" ]; then
    echo "   ❌ Actions API returned 404"
    echo "   → Actions are NOT enabled in Gitea"
    echo ""
    echo "   To enable, add to /etc/gitea/app.ini:"
    echo "   [actions]"
    echo "   ENABLED = true"
    echo "   DEFAULT_ACTIONS_URL = https://gitea.com"
elif [ "$HTTP_CODE" = "000" ]; then
    echo "   ⚠️  Cannot connect to ${GITEA_URL}"
else
    echo "   ⚠️  Unexpected response: HTTP ${HTTP_CODE}"
fi

# Check 6: Check for workflow runs
echo ""
echo "6️⃣ Checking for workflow runs..."
echo "   Visit: ${REPO_URL}/actions"
echo ""
echo "   If the Actions tab doesn't exist, Actions are not enabled."

# Check 7: Recent commits
echo ""
echo "7️⃣ Recent commits that should have triggered workflows:"
git log --oneline -5 --decorate

# Summary and next steps
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📋 TROUBLESHOOTING CHECKLIST"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Run these checks on your Gitea server:"
echo ""
echo "1️⃣ Check if Actions are enabled:"
echo "   grep -A 5 '\\[actions\\]' /etc/gitea/app.ini"
echo ""
echo "   Should show:"
echo "   [actions]"
echo "   ENABLED = true"
echo ""
echo "2️⃣ Check if a runner is registered:"
echo "   Visit: ${REPO_URL}/settings/actions/runners"
echo "   Should show at least 1 active runner"
echo ""
echo "3️⃣ Check Gitea logs for errors:"
echo "   sudo journalctl -u gitea -n 100 --no-pager | grep -i action"
echo ""
echo "4️⃣ Check runner logs (if installed as service):"
echo "   sudo journalctl -u act_runner -n 50 --no-pager"
echo ""
echo "5️⃣ Verify GIT_TOKEN secret exists:"
echo "   Visit: ${REPO_URL}/settings/secrets"
echo "   Should list: GIT_TOKEN"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔧 QUICK FIX COMMANDS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "If Actions are not enabled, run on your Gitea server:"
echo ""
echo "sudo tee -a /etc/gitea/app.ini > /dev/null <<EOF"
echo ""
echo "[actions]"
echo "ENABLED = true"
echo "DEFAULT_ACTIONS_URL = https://gitea.com"
echo "EOF"
echo ""
echo "sudo systemctl restart gitea"
echo ""
echo "Then install a runner:"
echo "wget https://dl.gitea.com/act_runner/0.2.6/act_runner-0.2.6-linux-amd64 -O /tmp/act_runner"
echo "chmod +x /tmp/act_runner"
echo "sudo mv /tmp/act_runner /usr/local/bin/"
echo ""
echo "Get registration token from:"
echo "  ${REPO_URL}/settings/actions/runners"
echo ""
echo "Then register:"
echo "  act_runner register --instance ${GITEA_URL} --labels ubuntu-latest"
echo ""
