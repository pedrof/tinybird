## Gitea Actions Setup Guide

This guide explains how to configure Gitea Actions to build and push container images to your Gitea package registry.

## Overview

The CI/CD pipeline includes three workflows:

1. **build-and-push.yaml**: Builds Traffic Analytics from source, mirrors Tinybird Local, pushes to your registry
2. **mirror-images.yaml**: Weekly job to keep upstream images in sync
3. **validate.yaml**: Validates Kubernetes manifests on PRs

## Prerequisites

### 1. Enable Gitea Actions

Verify Actions are enabled in your Gitea configuration (`/etc/gitea/app.ini`):

```ini
[actions]
ENABLED = true
DEFAULT_ACTIONS_URL = https://gitea.com

[packages]
ENABLED = true
```

Restart Gitea after changes:
```bash
sudo systemctl restart gitea
```

### 2. Register Actions Runner

You need at least one Gitea Actions runner to execute workflows:

```bash
# Download act_runner
wget https://dl.gitea.com/act_runner/0.2.6/act_runner-0.2.6-linux-amd64 -O act_runner
chmod +x act_runner
sudo mv act_runner /usr/local/bin/

# Generate configuration
act_runner generate-config > runner-config.yaml

# Register runner with your Gitea instance
act_runner register \
  --instance https://git.shadyknollcave.io \
  --token <RUNNER_REGISTRATION_TOKEN> \
  --name homelab-runner \
  --labels ubuntu-latest

# Run as daemon
act_runner daemon
```

**Get runner registration token:**
1. Go to `https://git.shadyknollcave.io/micro/tinybird/settings/actions/runners`
2. Click "Create new runner"
3. Copy the registration token

Or install as systemd service:

```bash
sudo cat > /etc/systemd/system/act_runner.service <<EOF
[Unit]
Description=Gitea Actions Runner
After=network.target

[Service]
Type=simple
User=gitea
WorkingDirectory=/var/lib/gitea/act_runner
ExecStart=/usr/local/bin/act_runner daemon
Restart=always

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now act_runner
```

## Required Secrets

### Create Gitea Access Token

Create a token with package write access:

```bash
# Via web UI:
# 1. Go to https://git.shadyknollcave.io/user/settings/applications
# 2. Generate New Token
# 3. Name: "Gitea Actions CI"
# 4. Scopes: Check "write:package"
# 5. Copy the token

# Or via tea CLI:
tea token create --name gitea-actions-ci --scopes write:package
```

### Add Secret to Repository

```bash
# Via web UI:
# 1. Go to https://git.shadyknollcave.io/micro/tinybird/settings/secrets
# 2. Add new secret
# 3. Name: GIT_TOKEN
# 4. Value: <paste token>
# 5. Save

# Or via tea CLI:
tea repo secret create --name GIT_TOKEN --data <token>
```

## Workflow Configuration

The workflows are located in `.gitea/workflows/` and use podman (per your preference) instead of docker.

### Key Features

- **Podman-based builds**: Uses `podman build` and `podman push`
- **Multi-tagging**: Automatic semver, SHA, and date-based tags
- **Auto-update manifests**: Updates Kustomize overlays with new image tags
- **Platform targeting**: Builds for linux/amd64

## Testing the Pipeline

### Manual Trigger

```bash
# Via web UI:
# Go to https://git.shadyknollcave.io/micro/tinybird/actions
# Click on a workflow → "Run workflow"

# Or push a commit:
git commit --allow-empty -m "test: trigger CI pipeline"
git push origin main
```

### Watch Workflow

```bash
# Via web UI:
# https://git.shadyknollcave.io/micro/tinybird/actions

# Check runner logs:
sudo journalctl -u act_runner -f
```

## Verify Images

After successful workflow run:

```bash
# View packages via web UI:
# https://git.shadyknollcave.io/micro/-/packages

# Or via API:
curl -u micro:$GIT_TOKEN \
  https://git.shadyknollcave.io/api/v1/packages/micro?type=container

# Pull image locally:
podman pull git.shadyknollcave.io/micro/tinybird-local:latest
podman pull git.shadyknollcave.io/micro/traffic-analytics:latest
```

## Troubleshooting

### Workflow not triggering

**Check Actions status:**
```bash
# In Gitea app.ini
[actions]
ENABLED = true

# Restart Gitea
sudo systemctl restart gitea
```

**Check runner status:**
```bash
sudo systemctl status act_runner
sudo journalctl -u act_runner -n 100
```

### "Error: registry authentication failed"

**Verify token scope:**
```bash
# Token needs write:package scope
curl -H "Authorization: token $GIT_TOKEN" \
  https://git.shadyknollcave.io/api/v1/user
```

### "Error: no runner available"

**Check runner registration:**
```bash
act_runner list
# Should show at least one runner with "ubuntu-latest" label
```

**Re-register runner:**
```bash
act_runner register \
  --instance https://git.shadyknollcave.io \
  --token <RUNNER_REGISTRATION_TOKEN> \
  --labels ubuntu-latest
```

### Podman build fails

**Check runner has podman:**
```bash
# SSH into runner host
podman version

# If missing, install:
sudo apt-get install -y podman
```

## ArgoCD Integration

After images are built and manifests updated:

```bash
# Verify kustomization was updated
git pull origin main
cat k8s/overlays/prod/kustomization.yaml

# Sync with ArgoCD
argocd app sync tinybird-analytics

# Watch deployment
kubectl get pods -n analytics -w
```

## Image Tags

Workflows create multiple tags:

```
# Latest (main branch)
git.shadyknollcave.io/micro/traffic-analytics:latest
git.shadyknollcave.io/micro/tinybird-local:latest

# Branch + SHA
git.shadyknollcave.io/micro/traffic-analytics:main-a1b2c3d

# Semver (on tag push)
git.shadyknollcave.io/micro/traffic-analytics:v1.0.0
git.shadyknollcave.io/micro/traffic-analytics:1.0
git.shadyknollcave.io/micro/traffic-analytics:1

# Date-based (mirrors)
git.shadyknollcave.io/micro/tinybird-local:20260216
```

## Security

✅ **Best Practices:**
- Use scoped tokens (write:package only)
- Store tokens in Gitea Secrets
- Enable runner isolation
- Regular token rotation

## Next Steps

1. **Tag a release:**
   ```bash
   git tag -a v1.0.0 -m "Initial release"
   git push origin v1.0.0
   ```

2. **Trigger workflow:**
   - Workflow runs automatically on tag push
   - Builds versioned images

3. **Deploy:**
   ```bash
   argocd app sync tinybird-analytics
   ```

## Resources

- [Gitea Actions Documentation](https://docs.gitea.com/usage/actions/overview)
- [Act Runner Setup](https://docs.gitea.com/usage/actions/act-runner)
- [Gitea Package Registry](https://docs.gitea.com/usage/packages/container)
