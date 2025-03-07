#!/bin/bash
set -e

# Despliega infraestructura de observabilidad
echo "Desplegando componentes de observabilidad..."
kubectl apply -f observability_kubernetes_base/deployment_jaeger.yaml
kubectl apply -f observability_kubernetes_base/deployment_loki.yaml
kubectl apply -f observability_kubernetes_base/deployment_opentelemetry.yaml
kubectl apply -f observability_kubernetes_base/deployment_grafana.yaml

# Espera a que los pods estén listos
echo "Esperando a que los componentes de observabilidad estén listos..."
kubectl wait --for=condition=ready pod -l app=jaeger --timeout=120s
kubectl wait --for=condition=ready pod -l app=loki --timeout=120s
kubectl wait --for=condition=ready pod -l app=opentelemetry-collector --timeout=120s
kubectl wait --for=condition=ready pod -l app=grafana --timeout=120s

# Despliega los microservicios
echo "Desplegando microservicios..."
kubectl apply -f micro-1/deployment.yaml
kubectl apply -f micro-2/deployment.yaml
kubectl apply -f micro-3/deployment.yaml

kubectl rollout restart deployment

echo "Laboratorio desplegado correctamente!"
echo "URLs de acceso:"
echo "Grafana: $(minikube service grafana --url)"
echo "Jaeger: $(minikube service jaeger --url)"