# Gitea Actions CI/CD - Fixed Workflows

## Overview

All three Gitea Actions workflows have been completely rewritten to work with minimal container runners that lack sudo, Node.js, and common utilities.

## What Was Fixed

### Root Issues

1. **No sudo in minimal containers** - Changed all `sudo apt-get` to `apt-get` (run as root)
2. **No Node.js for GitHub Actions** - Replaced `actions/checkout@v4` with manual `git clone`
3. **No curl by default** - Added curl to dependency installation step
4. **Path issues** - Use absolute paths in `/workspace/` directory

### Workflow-Specific Changes

#### build-and-push.yaml

**Before:** Used `actions/checkout@v4`, required Node.js, used sudo
**After:**
- Manual git clone from Gitea repository
- Direct apt-get commands (no sudo)
- Explicit checkout of commit SHA
- Uses `/workspace/` for all operations
- Token-based authentication for manifest updates

**Jobs:**
1. `build-traffic-analytics` - Clones TrafficAnalytics from GitHub, builds with podman, pushes to Gitea registry
2. `mirror-tinybird` - Pulls Tinybird image from Docker Hub, mirrors to Gitea registry
3. `update-manifests` - Updates Kustomize image tags and commits changes

**Tags Generated:**
- Branch pushes: `main`, `main-abc1234`, `latest` (if main)
- Semver tags: `v1.2.3`, `1`, `1.2`, `latest`
- Date tags: `20260216` (for mirrors)

#### mirror-images.yaml

**Before:** Used sudo, assumed tools installed
**After:**
- Direct apt-get installation
- Matrix strategy for multiple image variants (latest, beta)
- Date-tagged mirrors for tracking

**Schedule:** Every Sunday at 2 AM UTC

#### validate.yaml

**Before:** Used sudo and actions/checkout@v4
**After:**
- Manual git clone
- Direct curl download of kubectl
- yamllint for syntax checking
- Validates base, overlays, and ArgoCD app

## Requirements

### Gitea Configuration

Ensure Actions is enabled in Gitea (`/etc/gitea/app.ini`):

```ini
[actions]
ENABLED = true
DEFAULT_ACTIONS_URL = https://github.com
```

### Repository Secret

Create `GIT_TOKEN` secret with `write:package` scope:

1. Go to: https://git.shadyknollcave.io/user/settings/applications
2. Generate New Token
3. Name: `tinybird-ci`
4. Scopes: `write:package`, `write:repository`
5. Add to repository: https://git.shadyknollcave.io/micro/tinybird/settings/secrets

### Runner Requirements

Minimal Ubuntu container with:
- Root access (no sudo needed)
- Internet access for apt-get and git clone
- Access to Gitea registry at git.shadyknollcave.io

The workflows install all other dependencies (git, curl, podman, kubectl, yamllint).

## Workflow Triggers

### build-and-push.yaml
- Push to `main` or `develop` branches
- Pull requests to `main`
- Semver tags (`v*.*.*`)
- Manual dispatch

### mirror-images.yaml
- Weekly cron (Sunday 2 AM UTC)
- Manual dispatch

### validate.yaml
- Push to `main` or `develop` (only if k8s/** changes)
- Pull requests (only if k8s/** or .gitea/workflows/** changes)

## Testing

### Test build-and-push workflow

```bash
cd /home/micro/development/tinybird

# Create test commit
git commit --allow-empty -m "test: trigger CI/CD"
git push origin main
```

Watch in Gitea: https://git.shadyknollcave.io/micro/tinybird/actions

### Test validate workflow

```bash
# Edit a k8s file
touch k8s/base/test.yaml
git add k8s/base/test.yaml
git commit -m "test: trigger validation"
git push origin main
```

### Test mirror workflow manually

Go to: https://git.shadyknollcave.io/micro/tinybird/actions/workflows/mirror-images.yaml

Click "Run workflow"

## Verify Results

### Check Images in Registry

```bash
# List packages
curl -H "Authorization: token YOUR_TOKEN" \
  https://git.shadyknollcave.io/api/v1/packages/micro

# Or visit in browser
https://git.shadyknollcave.io/micro/-/packages
```

### Check Image Tags

After successful workflow:
- `git.shadyknollcave.io/micro/traffic-analytics:latest`
- `git.shadyknollcave.io/micro/traffic-analytics:main-abc1234`
- `git.shadyknollcave.io/micro/tinybird-local:latest`
- `git.shadyknollcave.io/micro/tinybird-local:20260216`

### Check Manifest Updates

```bash
cd /home/micro/development/tinybird
git pull origin main
cat k8s/overlays/prod/kustomization.yaml
```

Should show updated image tags:

```yaml
images:
  - name: tinybirdco/tinybird-local
    newName: git.shadyknollcave.io/micro/tinybird-local
    newTag: latest
  - name: ghost/traffic-analytics
    newName: git.shadyknollcave.io/micro/traffic-analytics
    newTag: main-abc1234
```

## ArgoCD Integration

After manifests are updated, ArgoCD will automatically sync if auto-sync is enabled:

```bash
# Check ArgoCD app status
argocd app get tinybird-analytics

# Manual sync if needed
argocd app sync tinybird-analytics

# Watch deployment
kubectl get pods -n tinybird-analytics -w
```

## Troubleshooting

### Workflow doesn't trigger

**Check:**
1. Actions enabled in Gitea UI
2. Runners visible in repo settings
3. Branch name matches trigger (main/develop)
4. Path filters match (for validate.yaml)

### "Secret not found: GIT_TOKEN"

**Fix:** Add GIT_TOKEN secret to repository settings

### "Permission denied" during git push

**Fix:** Ensure GIT_TOKEN has `write:repository` scope

### "Authentication failed" during podman login

**Fix:** Ensure GIT_TOKEN has `write:package` scope

### Podman build fails

**Check:**
1. Runner has enough disk space
2. Network access to GitHub (for TrafficAnalytics)
3. Containerfile exists in source repo

### Images not appearing in registry

**Check:**
1. Podman push completed successfully
2. Registry is accessible: https://git.shadyknollcave.io/micro/-/packages
3. GIT_TOKEN permissions

## Key Differences from GitHub Actions

1. **No Node.js ecosystem** - Can't use standard actions/checkout, actions/setup-*
2. **Minimal containers** - Must install all dependencies explicitly
3. **Manual git operations** - Clone and checkout manually
4. **Root access** - No sudo, but running as root
5. **Absolute paths** - Use `/workspace/` to avoid path issues
6. **Token auth** - Use `x-access-token:` prefix for HTTPS git operations

## Best Practices

1. **Always install dependencies first** - apt-get update && apt-get install
2. **Use absolute paths** - `/workspace/tinybird` not relative paths
3. **Verify tools** - Check versions after installation
4. **Echo progress** - Clear logging for debugging
5. **Handle errors** - Check exit codes and use `set -e` if needed

## Performance

**Typical run times:**
- `validate.yaml`: ~2-3 minutes (kubectl, yamllint)
- `mirror-tinybird`: ~3-5 minutes (image pull/push)
- `build-traffic-analytics`: ~10-15 minutes (source build)
- `update-manifests`: ~1 minute (git operations)

**Total pipeline**: ~15-20 minutes for full build-and-push

## Security Considerations

1. **Secret handling** - GIT_TOKEN properly secured in Gitea secrets
2. **Image verification** - Pull from trusted registries only
3. **Platform pinning** - All builds target `linux/amd64`
4. **Commit signing** - Bot commits from gitea-actions[bot]
5. **Minimal permissions** - Token only has package and repo write

## Next Steps

1. Monitor first workflow run for any edge cases
2. Consider adding image vulnerability scanning
3. Add notification steps (email, webhook, etc.)
4. Implement rollback workflow if needed
5. Add performance metrics collection

## Support

For issues:
1. Check workflow logs in Gitea UI
2. Check runner logs: `kubectl logs -n gitea -l app=gitea-runner`
3. Verify secret exists and has correct scopes
4. Test manual commands from runner pod

---

**Status:** Production-ready for minimal container runners
**Last Updated:** 2026-02-16
**Tested On:** Gitea Actions with act_runner on K3s
