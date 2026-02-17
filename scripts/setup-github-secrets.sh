#!/bin/bash
set -euo pipefail

# Setup GitHub Secrets for CI/CD Pipeline
# This script helps configure the required secrets for GitHub Actions

GITHUB_REPO="pedrof/tinybird"

echo "🔐 GitHub Actions Secrets Setup"
echo ""

# Check for required tools
command -v gh >/dev/null 2>&1 || { echo "❌ gh CLI not found. Install: https://cli.github.com/"; exit 1; }
command -v tea >/dev/null 2>&1 || { echo "⚠️  tea CLI not found. Some features will be limited."; }

# Verify GitHub authentication
echo "📋 Checking GitHub authentication..."
if ! gh auth status >/dev/null 2>&1; then
    echo "❌ Not authenticated with GitHub"
    echo "Run: gh auth login"
    exit 1
fi
echo "   ✅ Authenticated with GitHub"

# Check if repo exists
echo ""
echo "📦 Checking repository access..."
if ! gh repo view "$GITHUB_REPO" >/dev/null 2>&1; then
    echo "❌ Cannot access repository: $GITHUB_REPO"
    exit 1
fi
echo "   ✅ Repository accessible: $GITHUB_REPO"

# Create Gitea token
echo ""
echo "🔑 Gitea Access Token Setup"
echo ""
echo "You need to create a Gitea access token with 'write:package' scope."
echo ""
echo "Option 1: Create via Gitea web UI"
echo "  1. Go to https://git.shadyknollcave.io"
echo "  2. Settings → Applications → Generate New Token"
echo "  3. Name: 'GitHub Actions CI'"
echo "  4. Scopes: Check 'write:package'"
echo "  5. Copy the token"
echo ""

if command -v tea >/dev/null 2>&1; then
    echo "Option 2: Create via tea CLI"
    echo "  Run: tea token create --name github-actions-ci --scopes write:package"
    echo ""
    read -p "Create token now with tea CLI? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        if tea token create --name github-actions-ci --scopes write:package; then
            echo "   ✅ Token created successfully"
            echo "   Copy the token from above"
        else
            echo "   ⚠️  Token creation failed or token already exists"
        fi
    fi
    echo ""
fi

# Add secret to GitHub
echo "📝 Adding GITEA_TOKEN secret to GitHub repository..."
echo ""
echo "Please paste your Gitea token when prompted."
echo "The token will be securely stored in GitHub Secrets."
echo ""

if gh secret set GITEA_TOKEN --repo "$GITHUB_REPO"; then
    echo ""
    echo "   ✅ GITEA_TOKEN secret added successfully"
else
    echo ""
    echo "   ❌ Failed to add secret"
    exit 1
fi

# Verify secret was added
echo ""
echo "🔍 Verifying secrets configuration..."
if gh secret list --repo "$GITHUB_REPO" | grep -q "GITEA_TOKEN"; then
    echo "   ✅ GITEA_TOKEN is configured"
else
    echo "   ❌ GITEA_TOKEN not found in secrets"
    exit 1
fi

# List all secrets
echo ""
echo "📋 Current secrets in repository:"
gh secret list --repo "$GITHUB_REPO"

# Test workflow
echo ""
echo "🧪 Ready to test the workflow?"
read -p "Trigger a test workflow run? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "   Triggering workflow..."
    if gh workflow run build-and-push.yaml --repo "$GITHUB_REPO"; then
        echo "   ✅ Workflow triggered"
        echo ""
        echo "   Watch progress:"
        echo "     gh run watch --repo $GITHUB_REPO"
        echo ""
        sleep 2
        gh run watch --repo "$GITHUB_REPO" || true
    else
        echo "   ⚠️  Failed to trigger workflow"
    fi
fi

echo ""
echo "✅ Setup complete!"
echo ""
echo "📝 Next steps:"
echo "  1. Push a commit to trigger the workflow:"
echo "     git commit --allow-empty -m 'test: trigger CI pipeline'"
echo "     git push origin main && git push github main"
echo ""
echo "  2. Watch the workflow:"
echo "     gh run watch --repo $GITHUB_REPO"
echo ""
echo "  3. Verify images in Gitea registry:"
echo "     https://git.shadyknollcave.io/micro/-/packages"
echo ""
echo "  4. Deploy with ArgoCD:"
echo "     make argocd-deploy"
