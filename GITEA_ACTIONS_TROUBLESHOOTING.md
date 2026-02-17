# Gitea Actions Troubleshooting Guide

## Current Status

✅ **Workflows exist**: `.gitea/workflows/` directory with 3 workflow files
✅ **Workflows pushed**: Latest commit `2af6ac4` pushed to Gitea
✅ **Runners available**: 2x `ubuntu-latest` runners registered instance-wide
❓ **Actions enabled**: Need to verify
❓ **Secrets configured**: Need to verify

## Quick Diagnostics

### 1. Check if Gitea Actions is Enabled

Visit your Gitea instance and check:
```
https://git.shadyknollcave.io/micro/tinybird/actions
```

**If you see "404 Not Found" or no Actions tab:**
- Gitea Actions is NOT enabled on the server
- See "Enable Gitea Actions" section below

**If you see the Actions tab but no runs:**
- Actions is enabled, but workflows aren't triggering
- Check secrets and runner visibility

### 2. Verify Runners are Visible

Go to repository settings:
```
https://git.shadyknollcave.io/micro/tinybird/settings/actions/runners
```

**Expected**: Should list the instance-wide runners
- `runner-gitea-runner-5984b94bd6-5m766` (ubuntu-latest)
- `runner-gitea-runner-5984b94bd6-bdnwb` (ubuntu-latest)

**If no runners visible:**
- Runners are registered but not accessible to repo
- Check Gitea admin panel for runner registration

### 3. Check Required Secrets

Go to repository settings:
```
https://git.shadyknollcave.io/micro/tinybird/settings/secrets
```

**Required secret:**
- `GIT_TOKEN`: Gitea Personal Access Token with `write:package` scope

**To create:**
1. Go to `https://git.shadyknollcave.io/user/settings/applications`
2. Generate New Token
3. Name: `tinybird-ci`
4. Scopes: Select `write:package` (for container registry)
5. Generate Token
6. Copy the token
7. Add to repository secrets as `GIT_TOKEN`

## Enable Gitea Actions

If Actions is not enabled, you need to update Gitea configuration:

### Option 1: Via Gitea Admin Panel (Recommended)

1. Log in as admin to Gitea
2. Go to Site Administration > Configuration
3. Look for `[actions]` section
4. If not present or `ENABLED = false`, you need to edit the config file

### Option 2: Via Configuration File

SSH to your Gitea server and edit `/etc/gitea/app.ini`:

```bash
sudo nano /etc/gitea/app.ini
```

Add or update the `[actions]` section:

```ini
[actions]
ENABLED = true
DEFAULT_ACTIONS_URL = https://github.com
```

**Note**: `DEFAULT_ACTIONS_URL` allows using GitHub actions as fallback (e.g., `actions/checkout@v4`)

Restart Gitea:

```bash
sudo systemctl restart gitea
# or
kubectl rollout restart deployment/gitea -n gitea
```

## Verify Runner Registration

Check that runners are registered at the instance level:

### From Gitea Admin Panel

1. Go to `https://git.shadyknollcave.io/admin/actions/runners`
2. Should show 2 runners with label `ubuntu-latest`
3. Status should be "Online" or "Idle"

### From Kubernetes

```bash
# Check runner logs
kubectl logs -n gitea -l app=gitea-runner -c runner --tail=50

# Look for:
# - "Runner registered successfully"
# - "declare successfully"
```

## Test Workflow Manually

Once everything is configured, test the workflow:

### Option 1: Trigger via Push

```bash
cd ~/development/tinybird

# Make a change that matches workflow triggers
touch k8s/test-trigger.txt
git add k8s/test-trigger.txt
git commit -m "test: trigger workflow"
git push origin main
```

### Option 2: Manual Dispatch

If your workflow has `workflow_dispatch` trigger, you can run it manually from:
```
https://git.shadyknollcave.io/micro/tinybird/actions/workflows/build-and-push.yaml
```

Click "Run workflow"

## Expected Workflow Behavior

When working correctly:

1. **Push to Gitea** → Workflow triggers
2. **Runner picks up job** → Check runner logs: `kubectl logs -n gitea -l app=gitea-runner -c runner -f`
3. **Workflow executes** → View in Gitea UI: `https://git.shadyknollcave.io/micro/tinybird/actions`
4. **Images pushed** → Check registry: `https://git.shadyknollcave.io/micro/-/packages`

## Common Issues

### Issue: "No runners available"

**Cause**: Runners not registered or not visible to repo
**Fix**:
1. Check runner logs: `kubectl logs -n gitea -l app=gitea-runner -c runner`
2. Verify registration URL matches: `https://git.shadyknollcave.io`
3. Check runner token is valid

### Issue: "Secret not found: GIT_TOKEN"

**Cause**: Repository secret not configured
**Fix**: Add `GIT_TOKEN` secret in repo settings (see step 3 above)

### Issue: Workflows don't trigger on push

**Cause**: Path filters or branch mismatch
**Fix**:
- `validate.yaml` only triggers on changes to `k8s/**` or `.gitea/workflows/**`
- `build-and-push.yaml` triggers on ANY push to main/develop
- Try: `git commit --allow-empty -m "test" && git push origin main`

### Issue: "Authentication failed" during image push

**Cause**: `GIT_TOKEN` doesn't have `write:package` scope
**Fix**: Regenerate token with correct scope

## Debug Commands

```bash
# Check if Gitea Actions is enabled (from server)
grep -A 5 '\\[actions\\]' /etc/gitea/app.ini

# Check Gitea logs for Actions errors
kubectl logs -n gitea -l app.kubernetes.io/name=gitea --tail=100 | grep -i action

# Check runner status
kubectl get pods -n gitea -l app=gitea-runner
kubectl describe pod -n gitea -l app=gitea-runner

# Watch runner for incoming jobs
kubectl logs -n gitea -l app=gitea-runner -c runner -f
```

## Next Steps

1. ✅ Visit `https://git.shadyknollcave.io/micro/tinybird/actions`
2. ✅ If 404, enable Actions in Gitea config
3. ✅ Add `GIT_TOKEN` secret to repository
4. ✅ Verify runners are visible in repo settings
5. ✅ Push a test commit to trigger workflow
6. ✅ Watch workflow execute in Gitea UI

---

**Need Help?**

If workflows still don't trigger after following these steps, share:
- Screenshot of `https://git.shadyknollcave.io/micro/tinybird/actions`
- Output of: `kubectl logs -n gitea -l app.kubernetes.io/name=gitea --tail=50 | grep -i action`
- Whether you can see the Actions tab in Gitea UI
