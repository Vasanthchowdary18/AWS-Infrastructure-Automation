#!/usr/bin/env bash
# Installs metrics-server, kube-prometheus-stack (Prometheus + Grafana + Alertmanager),
# then the app's ServiceMonitor, alert rules and Grafana dashboard.
set -euo pipefail

GRAFANA_PASSWORD="${GRAFANA_PASSWORD:?Set GRAFANA_PASSWORD env var first}"
cd "$(dirname "$0")/.."

# metrics-server (needed by the HPA)
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  -f monitoring/prometheus-values.yaml \
  --set grafana.adminPassword="${GRAFANA_PASSWORD}" \
  --wait --timeout 10m

kubectl apply -f k8s/namespace.yaml
kubectl apply -f monitoring/servicemonitor.yaml \
              -f monitoring/alert-rules.yaml \
              -f monitoring/grafana-dashboard.yaml

echo "Grafana URL: http://$(kubectl -n monitoring get svc monitoring-grafana -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"
echo "Login: admin / <your GRAFANA_PASSWORD>"
