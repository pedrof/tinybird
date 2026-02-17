# Gitea Actions Testing Checklist

## Pre-Flight Checks

### 1. Verify Gitea Actions is Enabled

- [ ] Visit: https://git.shadyknollcave.io/micro/tinybird/actions
- [ ] Confirm Actions tab is visible (not 404)
- [ ] Check if any workflows are listed

### 2. Verify Runners are Available

- [ ] Visit: https://git.shadyknollcave.io/micro/tinybird/settings/actions/runners
- [ ] Confirm at least one `ubuntu-latest` runner is visible
- [ ] Check runner status is "Idle" or "Active"

### 3. Verify Secret Configuration

- [ ] Visit: https://git.shadyknollcave.io/micro/tinybird/settings/secrets
- [ ] Confirm `GIT_TOKEN` secret exists
- [ ] Token must have scopes:
  - `write:package` (for container registry)
  - `write:repository` (for manifest updates)

**If secret doesn't exist:**
```bash
# Create token at:
https://git.shadyknollcave.io/user/settings/applications

# Name: tinybird-ci
# Scopes: write:package, write:repository
# Add to repo secrets as: GIT_TOKEN
```

## Test 1: Validate Workflow

**Purpose:** Verify manifest validation works
**Trigger:** Push changes to k8s/** directory

### Steps

```bash
cd /home/micro/development/tinybird

# Make a trivial change
touch k8s/test-$(date +%s).txt

# Commit and push
git add k8s/
git commit -m "test: trigger validate workflow"
git push origin main
```

### Expected Results

- [ ] Workflow appears in Actions tab within 30 seconds
- [ ] Runner picks up job (status: "Running")
- [ ] All steps complete successfully:
  - [ ] Install dependencies
  - [ ] Checkout repository
  - [ ] Set up kubectl
  - [ ] Validate base manifests
  - [ ] Validate production overlay
  - [ ] Check YAML syntax
  - [ ] Validate ArgoCD application
- [ ] Final status: SUCCESS (green checkmark)
- [ ] Runtime: ~2-3 minutes

### Troubleshooting

**If workflow doesn't trigger:**
- Check path filter matches: `k8s/**` or `.gitea/workflows/**`
- Try empty commit: `git commit --allow-empty -m "test" && git push`

**If "Install dependencies" fails:**
- Check runner has internet access
- Check runner has apt-get available
- Verify runner is Ubuntu-based

**If kubectl validation fails:**
- Check manifest YAML syntax
- Verify kustomization.yaml is valid
- Check ArgoCD app references correct paths

## Test 2: Mirror Images Workflow

**Purpose:** Verify image mirroring from Docker Hub
**Trigger:** Manual dispatch (safer for first test)

### Steps

1. Visit: https://git.shadyknollcave.io/micro/tinybird/actions/workflows/mirror-images.yaml
2. Click "Run workflow" button
3. Select branch: `main`
4. Click "Run"

### Expected Results

- [ ] Two jobs start (matrix strategy):
  - [ ] Mirror Tinybird Local (latest)
  - [ ] Mirror Tinybird Local Beta (beta)
- [ ] Each job completes:
  - [ ] Install dependencies
  - [ ] Verify Podman
  - [ ] Log in to registry
  - [ ] Pull upstream image
  - [ ] Tag for local registry
  - [ ] Push to registry (2 tags: base + date)
- [ ] Final status: SUCCESS for both jobs
- [ ] Runtime: ~3-5 minutes per job

### Verify Images

```bash
# Check registry via API
curl -H "Authorization: token YOUR_TOKEN" \
  https://git.shadyknollcave.io/api/v1/packages/micro

# Or visit web UI
https://git.shadyknollcave.io/micro/-/packages
```

**Expected packages:**
- [ ] `tinybird-local:latest`
- [ ] `tinybird-local:latest-20260216` (today's date)
- [ ] `tinybird-local:beta`
- [ ] `tinybird-local:beta-20260216`

### Troubleshooting

**If "Log in to registry" fails:**
- Verify GIT_TOKEN secret exists
- Check token has `write:package` scope
- Test manual login: `echo "$TOKEN" | podman login git.shadyknollcave.io -u micro --password-stdin`

**If "Pull upstream image" fails:**
- Check runner has internet access to Docker Hub
- Verify image exists: docker.io/tinybirdco/tinybird-local:latest
- Check for rate limiting (Docker Hub)

**If "Push to registry" fails:**
- Verify registry is accessible
- Check Gitea container registry is enabled
- Verify token permissions

## Test 3: Build and Push Workflow

**Purpose:** Full CI/CD pipeline test
**Trigger:** Push to main branch

### Steps

```bash
cd /home/micro/development/tinybird

# Create test commit
git commit --allow-empty -m "test: trigger full build pipeline"
git push origin main
```

### Expected Results

**Job 1: build-traffic-analytics**
- [ ] Install dependencies (git, curl, podman)
- [ ] Checkout tinybird repository
- [ ] Clone TrafficAnalytics from GitHub
- [ ] Verify Podman
- [ ] Log in to registry
- [ ] Extract metadata (generate tags)
- [ ] Build Traffic Analytics (15+ minutes)
- [ ] Push all tags (latest, main, main-SHA)

**Job 2: mirror-tinybird**
- [ ] Install dependencies (podman)
- [ ] Verify Podman
- [ ] Log in to registry
- [ ] Pull Tinybird image from Docker Hub
- [ ] Tag for local registry
- [ ] Push images (latest, date tag)

**Job 3: update-manifests** (depends on jobs 1 & 2)
- [ ] Install dependencies (git)
- [ ] Configure Git
- [ ] Checkout with token auth
- [ ] Set image tags (main-SHA)
- [ ] Update Kustomize manifests
- [ ] Commit changes
- [ ] Push to main branch

**Final checks:**
- [ ] All 3 jobs SUCCESS
- [ ] Total runtime: ~15-20 minutes
- [ ] New commit appears in repo (manifest update)

### Verify Build Artifacts

**Check images in registry:**
- [ ] `traffic-analytics:latest`
- [ ] `traffic-analytics:main`
- [ ] `traffic-analytics:main-abc1234` (SHA)
- [ ] `tinybird-local:latest`
- [ ] `tinybird-local:20260216`

**Check manifest updates:**
```bash
cd /home/micro/development/tinybird
git pull origin main
cat k8s/overlays/prod/kustomization.yaml
```

Should show:
```yaml
images:
  - name: tinybirdco/tinybird-local
    newName: git.shadyknollcave.io/micro/tinybird-local
    newTag: latest
  - name: ghost/traffic-analytics
    newName: git.shadyknollcave.io/micro/traffic-analytics
    newTag: main-abc1234  # <-- Updated SHA
```

**Check ArgoCD sync:**
```bash
argocd app get tinybird-analytics
argocd app diff tinybird-analytics
```

### Troubleshooting

**If "Clone TrafficAnalytics" fails:**
- Check runner has internet access to GitHub
- Verify GitHub is not rate-limiting
- Check TrafficAnalytics repo still exists

**If "Build Traffic Analytics" fails:**
- Check build logs for errors
- Verify source has Dockerfile/Containerfile
- Check podman has enough disk space
- Verify no networking issues during build

**If "update-manifests" fails to push:**
- Verify GIT_TOKEN has `write:repository` scope
- Check no merge conflicts exist
- Verify Git config is correct
- Check branch protection rules

**If manifest commit creates loop:**
- Ensure workflow has `if: github.ref == 'refs/heads/main'` condition
- Check commit message doesn't trigger another run
- Verify [skip ci] or similar if needed

## Test 4: Semver Tag Release

**Purpose:** Test version tagging workflow
**Trigger:** Push semver tag

### Steps

```bash
cd /home/micro/development/tinybird

# Create and push semver tag
git tag -a v1.0.0 -m "Release v1.0.0"
git push origin v1.0.0
```

### Expected Results

- [ ] Workflow triggers on tag push
- [ ] Build creates version-specific tags:
  - [ ] `traffic-analytics:v1.0.0`
  - [ ] `traffic-analytics:1`
  - [ ] `traffic-analytics:1.0`
  - [ ] `tinybird-local:v1.0.0`
- [ ] Manifests updated with v1.0.0 tag
- [ ] All jobs complete successfully

### Cleanup

```bash
# Delete test tag if needed
git tag -d v1.0.0
git push origin :refs/tags/v1.0.0
```

## Test 5: Pull Request Validation

**Purpose:** Verify PR validation works
**Trigger:** Create pull request

### Steps

```bash
cd /home/micro/development/tinybird

# Create feature branch
git checkout -b test/pr-validation

# Make a change
echo "# Test" >> k8s/README.md
git add k8s/README.md
git commit -m "docs: test PR validation"

# Push and create PR
git push origin test/pr-validation

# Create PR in Gitea UI or with tea
tea pr create --title "Test PR validation" --description "Testing workflow"
```

### Expected Results

- [ ] Validate workflow triggers on PR
- [ ] Build workflow triggers on PR (but doesn't push/update)
- [ ] Status checks appear on PR
- [ ] All checks pass (green)
- [ ] PR can be merged

### Cleanup

```bash
# Delete test branch
git checkout main
git branch -D test/pr-validation
git push origin --delete test/pr-validation
```

## Runner Health Checks

### Check Runner Logs

```bash
# List runners
kubectl get pods -n gitea -l app=gitea-runner

# Follow logs
kubectl logs -n gitea -l app=gitea-runner -c runner -f

# Check for errors
kubectl logs -n gitea -l app=gitea-runner -c runner --tail=100 | grep -i error
```

### Runner Status

```bash
# Check runner pods
kubectl get pods -n gitea -l app=gitea-runner

# Expected: Running status
# NAME                                  READY   STATUS    RESTARTS   AGE
# runner-gitea-runner-5984b94bd6-xxxxx   2/2     Running   0          24h
```

### Test Runner Connectivity

```bash
# Exec into runner container
kubectl exec -it -n gitea deployment/gitea-runner -c runner -- bash

# Test registry access
podman login git.shadyknollcave.io -u micro

# Test git access
git clone https://git.shadyknollcave.io/micro/tinybird.git /tmp/test

# Test internet access
curl -I https://github.com
```

## Common Issues and Solutions

### Issue: Workflow doesn't trigger

**Solutions:**
1. Check Actions is enabled in Gitea
2. Verify runners are visible to repository
3. Check branch name matches trigger
4. Try manual dispatch first
5. Check Gitea logs for errors

### Issue: "Secret not found"

**Solutions:**
1. Add GIT_TOKEN in repo settings > Secrets
2. Verify secret name matches exactly: `GIT_TOKEN`
3. Check secret is not expired
4. Regenerate token with correct scopes

### Issue: "Permission denied"

**Solutions:**
1. Verify token has `write:package` and `write:repository` scopes
2. Check user has write access to repository
3. Verify registry is accessible
4. Test manual podman login

### Issue: Build timeout

**Solutions:**
1. Increase workflow timeout (default: 60 min)
2. Check for slow network connections
3. Verify no infinite loops in build
4. Check runner has adequate resources

## Success Criteria

All workflows passing means:

- [x] Workflows fixed and working on minimal containers
- [x] No sudo or Node.js dependencies
- [x] Images building and pushing to registry
- [x] Manifests automatically updated
- [x] ArgoCD can deploy from registry
- [x] Documentation complete

## Next Steps After Successful Tests

1. **Monitor production runs** - Watch first few automatic triggers
2. **Set up notifications** - Add failure alerts
3. **Performance tuning** - Optimize build times if needed
4. **Add more tests** - Integration tests, security scanning
5. **Document runbooks** - Incident response procedures

---

**Status:** Ready for testing
**Last Updated:** 2026-02-16
**Test Duration:** ~30-45 minutes for complete suite
