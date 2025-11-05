#!/bin/bash
set -e

echo "🔍 Validating Observability Stack..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to check service health
check_service() {
    local service_name=$1
    local service_url=$2
    local max_attempts=30
    local attempt=1

    echo -n "Checking $service_name... "
    
    while [ $attempt -le $max_attempts ]; do
        if curl -f --max-time 5 "$service_url" >/dev/null 2>&1; then
            echo -e "${GREEN}✓${NC}"
            return 0
        fi
        
        if [ $attempt -eq $max_attempts ]; then
            echo -e "${RED}✗${NC} (failed after $max_attempts attempts)"
            return 1
        fi
        
        sleep 2
        attempt=$((attempt + 1))
    done
}

# Function to validate metrics
validate_metrics() {
    echo -n "Validating metrics collection... "
    
    # Get metrics from Prometheus
    METRICS_RESPONSE=$(curl -s "http://localhost:${PROMETHEUS_PORT}/api/v1/query?query=up" 2>/dev/null || echo "")
    
    if echo "$METRICS_RESPONSE" | grep -q '"status":"success"'; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${YELLOW}⚠${NC} (metrics might not be fully collected yet)"
    fi
}

# Function to validate traces
validate_traces() {
    echo -n "Validating trace collection... "
    
    # Get services from Jaeger
    TRACES_RESPONSE=$(curl -s "http://localhost:${JAEGER_PORT}/api/services" 2>/dev/null || echo "")
    
    if echo "$TRACES_RESPONSE" | grep -q '"data":'; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${YELLOW}⚠${NC} (traces might not be fully collected yet)"
    fi
}

# Function to validate alerts
validate_alerts() {
    echo -n "Validating alert rules... "
    
    ALERTS_RESPONSE=$(curl -s "http://localhost:${PROMETHEUS_PORT}/api/v1/rules" 2>/dev/null || echo "")
    
    if echo "$ALERTS_RESPONSE" | grep -q '"status":"success"'; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${YELLOW}⚠${NC} (alert rules might not be configured properly)"
    fi
}

# Detectar si estamos usando minikube o Docker Desktop
USE_MINIKUBE=false
if command -v minikube > /dev/null 2>&1 && minikube status > /dev/null 2>&1; then
    USE_MINIKUBE=true
    echo "Detectado: minikube"
else
    echo "Detectado: Docker Desktop Kubernetes (o otro entorno)"
    echo "⚠️  Asegúrate de tener port-forwards activos para validar los servicios"
fi

# Get URLs según el entorno
if [ "$USE_MINIKUBE" = true ]; then
    PROMETHEUS_PORT=$(minikube service prometheus --url 2>/dev/null | cut -d: -f3 || echo "9090")
    JAEGER_PORT=$(minikube service jaeger --url 2>/dev/null | cut -d: -f3 || echo "16686")
    GRAFANA_PORT=$(minikube service grafana --url 2>/dev/null | cut -d: -f3 || echo "3000")
    ALERTMANAGER_PORT=$(minikube service alertmanager --url 2>/dev/null | cut -d: -f3 || echo "9093")
    OTEL_COLLECTOR_PORT=$(minikube service otel-collector --url 2>/dev/null | cut -d: -f3 || echo "8889")
    API_GATEWAY_PORT=$(minikube service api-gateway --url 2>/dev/null | cut -d: -f3 || echo "8080")
else
    # Docker Desktop - usar puertos por defecto (asumiendo port-forward)
    PROMETHEUS_PORT="9090"
    JAEGER_PORT="16686"
    GRAFANA_PORT="3000"
    ALERTMANAGER_PORT="9093"
    OTEL_COLLECTOR_PORT="8889"
    API_GATEWAY_PORT="8080"
fi

PROMETHEUS_URL="http://localhost:${PROMETHEUS_PORT}/-/healthy"
JAEGER_URL="http://localhost:${JAEGER_PORT}/api/services"
GRAFANA_URL="http://localhost:${GRAFANA_PORT}/api/health"
ALERTMANAGER_URL="http://localhost:${ALERTMANAGER_PORT}/-/healthy"
OTEL_COLLECTOR_URL="http://localhost:${OTEL_COLLECTOR_PORT}/metrics"
API_GATEWAY_URL="http://localhost:${API_GATEWAY_PORT}"

echo ""
echo "🧪 Service Health Checks:"

# Check each service
check_service "OpenTelemetry Collector" "$OTEL_COLLECTOR_URL" || true
check_service "Prometheus" "$PROMETHEUS_URL"
check_service "Jaeger" "$JAEGER_URL"
check_service "Grafana" "$GRAFANA_URL"
check_service "AlertManager" "$ALERTMANAGER_URL"

echo ""
echo "📊 Observability Validation:"

validate_metrics
validate_traces
validate_alerts

echo ""
echo "🎯 Generating Test Traffic..."

# Generate some test requests
for i in {1..5}; do
    curl -s "${API_GATEWAY_URL}/health" >/dev/null 2>&1 || echo "Warning: API Gateway not responding"
    sleep 1
done

echo "✅ Observability validation completed!"
echo ""
echo "🔗 Access URLs:"
if [ "$USE_MINIKUBE" = true ]; then
    echo "Grafana: $(minikube service grafana --url 2>/dev/null || echo 'http://localhost:3000')"
    echo "Jaeger: $(minikube service jaeger --url 2>/dev/null || echo 'http://localhost:16686')"
    echo "Prometheus: $(minikube service prometheus --url 2>/dev/null || echo 'http://localhost:9090')"
    echo "AlertManager: $(minikube service alertmanager --url 2>/dev/null || echo 'http://localhost:9093')"
else
    echo "Grafana: http://localhost:3000"
    echo "Jaeger: http://localhost:16686"
    echo "Prometheus: http://localhost:9090"
    echo "AlertManager: http://localhost:9093"
    echo "API Gateway: http://localhost:8080"
    echo ""
    echo "💡 Ejecuta port-forwards si aún no los tienes:"
    echo "   kubectl port-forward svc/grafana 3000:3000 &"
    echo "   kubectl port-forward svc/jaeger 16686:16686 &"
    echo "   kubectl port-forward svc/prometheus 9090:9090 &"
    echo "   kubectl port-forward svc/alertmanager 9093:9093 &"
    echo "   kubectl port-forward svc/api-gateway 8080:3000 &"
fi
