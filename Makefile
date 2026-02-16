.PHONY: help deploy delete status logs test validate

# Variables
NAMESPACE := analytics
KUSTOMIZE := kubectl apply -k
KUBECTL := kubectl -n $(NAMESPACE)

help: ## Show this help message
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Available targets:'
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-20s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

validate: ## Validate Kubernetes manifests
	@echo "Validating manifests..."
	kustomize build k8s/overlays/prod | kubectl apply --dry-run=client -f -
	@echo "✓ Manifests are valid"

deploy: ## Deploy to cluster
	@echo "Deploying Tinybird analytics..."
	$(KUSTOMIZE) k8s/overlays/prod
	@echo "✓ Deployed successfully"
	@echo "Waiting for rollout..."
	kubectl rollout status deployment/tinybird -n $(NAMESPACE)
	kubectl rollout status deployment/traffic-analytics -n $(NAMESPACE)

delete: ## Delete deployment
	@echo "Deleting Tinybird analytics..."
	$(KUSTOMIZE) k8s/overlays/prod --wait=false
	kubectl delete namespace $(NAMESPACE) --wait=false
	@echo "✓ Deleted"

status: ## Check deployment status
	@echo "=== Deployments ==="
	$(KUBECTL) get deployments
	@echo ""
	@echo "=== Pods ==="
	$(KUBECTL) get pods
	@echo ""
	@echo "=== Services ==="
	$(KUBECTL) get svc
	@echo ""
	@echo "=== Ingress ==="
	$(KUBECTL) get ingress
	@echo ""
	@echo "=== PVCs ==="
	$(KUBECTL) get pvc

logs-tinybird: ## Tail Tinybird logs
	$(KUBECTL) logs -l app=tinybird -f --tail=100

logs-proxy: ## Tail Traffic Analytics proxy logs
	$(KUBECTL) logs -l app=traffic-analytics -f --tail=100

test: ## Test endpoints
	@echo "Testing Tinybird API..."
	@curl -s https://tinybird.shadyknollcave.io/v0/ | jq . || echo "✗ Tinybird API not responding"
	@echo ""
	@echo "Testing Traffic Analytics proxy..."
	@curl -s https://analytics-proxy.shadyknollcave.io/health || echo "✗ Proxy not responding"

cert-status: ## Check certificate status
	@echo "=== Certificates ==="
	$(KUBECTL) get certificate
	@echo ""
	@echo "=== Certificate Details ==="
	$(KUBECTL) describe certificate tinybird-tls
	$(KUBECTL) describe certificate traffic-analytics-tls

argocd-deploy: ## Deploy ArgoCD application
	kubectl apply -f argocd-app.yaml -n argocd
	@echo "✓ ArgoCD application created"
	@echo "Check status: argocd app get tinybird-analytics"

argocd-delete: ## Delete ArgoCD application
	kubectl delete -f argocd-app.yaml -n argocd
	@echo "✓ ArgoCD application deleted"
