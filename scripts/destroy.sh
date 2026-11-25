#!/usr/bin/env bash
# Tears everything down so you stop paying for EKS, NAT gateway and load balancers.
set -euo pipefail
cd "$(dirname "$0")/.."

# Delete LoadBalancer services first so AWS ELBs don't block VPC deletion
kubectl delete namespace devops-app --ignore-not-found
helm uninstall monitoring -n monitoring || true
kubectl delete namespace monitoring --ignore-not-found

cd terraform
terraform destroy -auto-approve
