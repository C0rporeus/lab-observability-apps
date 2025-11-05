#!/bin/bash

set -e

echo "🔍 Verificando Logs y Trazas..."

echo ""
echo "1️⃣ Verificando Loki..."
kubectl port-forward svc/loki 3100:3100 > /dev/null 2>&1 &
LOKI_PID=$!
sleep 2

echo "  - Loki status:"
curl -s "http://localhost:3100/ready" && echo " ✅" || echo " ❌"

echo "  - Labels disponibles:"
curl -s "http://localhost:3100/loki/api/v1/labels" | python3 -m json.tool | grep -E "(\"data\"|\"status\")" | head -5

kill $LOKI_PID 2>/dev/null || true

echo ""
echo "2️⃣ Verificando Jaeger..."
kubectl port-forward svc/jaeger 16686:16686 > /dev/null 2>&1 &
JAEGER_PID=$!
sleep 2

echo "  - Servicios con trazas:"
curl -s "http://localhost:16686/api/services" | python3 -m json.tool | grep -A 10 "\"data\"" | head -10

kill $JAEGER_PID 2>/dev/null || true

echo ""
echo "3️⃣ Verificando OpenTelemetry Collector..."
echo "  - Logs del collector (últimas líneas relacionadas con logs):"
kubectl logs -l app=opentelemetry-collector --tail=50 | grep -i -E "(log|loki|error)" | tail -5 || echo "    (sin logs relacionados)"

echo ""
echo "4️⃣ Generando tráfico de prueba..."
API_GW_POD=$(kubectl get pods -l app=api-gateway -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$API_GW_POD" ]; then
    echo "  - Haciendo request a /weather/micro1?city=TestCity"
    kubectl exec $API_GW_POD -c api-gateway -- wget -qO- "http://localhost:3000/weather/micro1?city=TestCity" > /dev/null 2>&1 || echo "    (error al hacer request)"
    sleep 2
else
    echo "  - API Gateway no disponible"
fi

echo ""
echo "5️⃣ Verificando logs en Loki después del tráfico..."
kubectl port-forward svc/loki 3100:3100 > /dev/null 2>&1 &
LOKI_PID=$!
sleep 2

echo "  - Query para api-gateway:"
RESULT=$(curl -s -G "http://localhost:3100/loki/api/v1/query_range" \
  --data-urlencode 'query={service_name="api-gateway"}' \
  --data-urlencode 'limit=5' | python3 -m json.tool)
echo "$RESULT" | grep -E "(\"result\"|\"status\")" | head -5

kill $LOKI_PID 2>/dev/null || true

echo ""
echo "✅ Verificación completada"
echo ""
echo "📝 Para ver logs en Grafana:"
echo "   1. Abre http://localhost:3000"
echo "   2. Ve al dashboard 'Observability Stack - Overview'"
echo "   3. El panel 'API Gateway Logs' debería mostrar logs"
echo ""
echo "📝 Para ver trazas en Grafana:"
echo "   1. El panel 'Distributed Traces' debería mostrar trazas de api-gateway"
echo "   2. También puedes ver trazas directamente en Jaeger: kubectl port-forward svc/jaeger 16686:16686"
echo ""
