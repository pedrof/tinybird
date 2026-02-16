# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Initial K8s deployment for Tinybird Local
- Traffic Analytics Service proxy deployment
- Persistent volumes for ClickHouse and Redis data
- Ingress configuration with Let's Encrypt TLS
- ArgoCD GitOps integration
- Makefile for common operations
- Ghost blog integration documentation

### Infrastructure
- Namespace: analytics
- Deployments: tinybird, traffic-analytics
- Services: ClusterIP for internal communication
- Ingress: Cilium with TLS termination
- Storage: 10Gi for ClickHouse, 1Gi for Redis
