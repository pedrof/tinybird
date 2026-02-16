#!/bin/bash
set -euo pipefail

# Setup dual git remotes (Gitea + GitHub)
# Per user's workflow: primary Gitea, backup GitHub

PROJECT_NAME="tinybird"
GITEA_USER="micro"
GITHUB_USER="pedrof"

GITEA_URL="https://git.shadyknollcave.io/${GITEA_USER}/${PROJECT_NAME}"
GITHUB_URL="git@github.com:${GITHUB_USER}/${PROJECT_NAME}"

echo "🔧 Setting up dual git remotes for ${PROJECT_NAME}"
echo ""

# Check for required tools
command -v tea >/dev/null 2>&1 || { echo "❌ tea CLI not found"; exit 1; }
command -v gh >/dev/null 2>&1 || { echo "❌ gh CLI not found"; exit 1; }

# Create Gitea repo
echo "📦 Creating Gitea repository..."
if tea repos create \
    --name "${PROJECT_NAME}" \
    --description "Self-hosted Tinybird analytics for Ghost blog" \
    --private=false \
    2>/dev/null; then
    echo "   ✅ Gitea repo created: ${GITEA_URL}"
else
    echo "   ℹ️  Gitea repo might already exist: ${GITEA_URL}"
fi

# Create GitHub repo
echo ""
echo "📦 Creating GitHub repository..."
if gh repo create "${GITHUB_USER}/${PROJECT_NAME}" \
    --description "Self-hosted Tinybird analytics for Ghost blog (backup mirror)" \
    --public \
    2>/dev/null; then
    echo "   ✅ GitHub repo created: ${GITHUB_URL}"
else
    echo "   ℹ️  GitHub repo might already exist: ${GITHUB_URL}"
fi

# Add remotes
echo ""
echo "🔗 Adding git remotes..."

# Remove existing remotes if they exist
git remote remove gitea 2>/dev/null || true
git remote remove github 2>/dev/null || true
git remote remove origin 2>/dev/null || true

# Add Gitea as primary (origin)
git remote add origin "${GITEA_URL}.git"
echo "   ✅ Added origin → ${GITEA_URL}"

# Add GitHub as backup
git remote add github "${GITHUB_URL}.git"
echo "   ✅ Added github → ${GITHUB_URL}"

# Verify remotes
echo ""
echo "📋 Configured remotes:"
git remote -v

# Push to both remotes
echo ""
echo "🚀 Pushing to remotes..."

echo "   Pushing to Gitea (origin)..."
git push -u origin main

echo "   Pushing to GitHub..."
git push -u github main

echo ""
echo "✅ Setup complete!"
echo ""
echo "📝 Repository URLs:"
echo "   Primary (Gitea):  ${GITEA_URL}"
echo "   Backup (GitHub):  https://github.com/${GITHUB_USER}/${PROJECT_NAME}"
echo ""
echo "🔄 To push to both remotes:"
echo "   git push origin main && git push github main"
echo ""
echo "   Or add this alias to ~/.gitconfig:"
echo "   [alias]"
echo "       pushall = !git push origin main && git push github main"
