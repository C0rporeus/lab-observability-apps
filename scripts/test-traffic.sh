#!/bin/bash

set -e

echo "🚀 Generando Tráfico de Prueba para Observabilidad"
echo ""

# Verificar que el API Gateway está disponible
API_GW_POD=$(kubectl get pods -l app=api-gateway -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -z "$API_GW_POD" ]; then
    echo "❌ Error: API Gateway no está disponible"
    exit 1
fi

echo "✅ API Gateway encontrado: $API_GW_POD"
echo ""

# Función para hacer requests al API Gateway
make_request() {
    local endpoint=$1
    local method=${2:-GET}
    local data=${3:-""}
    
    if [ "$method" = "POST" ]; then
        curl -s -X POST "http://localhost:8080$endpoint" \
            -H "Content-Type: application/json" \
            -d "$data" > /dev/null
    else
        curl -s "http://localhost:8080$endpoint" > /dev/null
    fi
}

# Verificar que el port-forward está activo
if ! curl -s http://localhost:8080/health > /dev/null 2>&1; then
    echo "⚠️  Advertencia: No se puede conectar a http://localhost:8080"
    echo "   Asegúrate de tener el port-forward activo:"
    echo "   kubectl port-forward svc/api-gateway 8080:3000"
    echo ""
    read -p "¿Continuar de todos modos? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

echo "📊 Generando tráfico de prueba..."
echo ""

# 1. Requests a micro-2 (Go)
echo "1️⃣ Generando requests a micro-2..."
for city in London Paris Madrid Barcelona Tokyo; do
    echo "  → GET /weather/micro2?city=$city"
    make_request "/weather/micro2?city=$city"
    sleep 0.5
done
echo ""

# 2. Guardar datos en micro-2
echo "2️⃣ Guardando datos en micro-2..."
for i in {1..3}; do
    city=$(shuf -e London Paris Madrid -n 1)
    temp=$((15 + RANDOM % 15)).$((RANDOM % 99))
    humidity=$((50 + RANDOM % 30))
    windSpeed=$((RANDOM % 10)).$((RANDOM % 9))
    
    data=$(cat <<EOF
{
  "city": "$city",
  "temperature": $temp,
  "condition": "test",
  "humidity": $humidity,
  "windSpeed": $windSpeed
}
EOF
)
    echo "  → POST /weather/micro2/save (city: $city)"
    make_request "/weather/micro2/save" "POST" "$data"
    sleep 0.5
done
echo ""

# 3. Consultar historial de micro-2
echo "3️⃣ Consultando historial de micro-2..."
echo "  → GET /weather/micro2/history/all/10"
make_request "/weather/micro2/history/all/10"
sleep 0.5

echo "  → GET /weather/micro2/history/London/5"
make_request "/weather/micro2/history/London/5"
echo ""

# 4. Requests a micro-1 (Rust)
echo "4️⃣ Generando requests a micro-1..."
for city in Rome Berlin Amsterdam; do
    echo "  → GET /weather/micro1?city=$city"
    make_request "/weather/micro1?city=$city"
    sleep 0.5
done
echo ""

# 5. Consultar historial de micro-1
echo "5️⃣ Consultando historial de micro-1..."
echo "  → GET /weather/micro1/history/10"
make_request "/weather/micro1/history/10"
sleep 0.5

echo "  → GET /weather/micro1/history/Rome/5"
make_request "/weather/micro1/history/Rome/5"
echo ""

echo "✅ Tráfico generado exitosamente"
echo ""
echo "📋 Verificación de Observabilidad:"
echo ""
echo "1️⃣ Verificar logs del collector:"
echo "   kubectl logs -l app=opentelemetry-collector --tail=50 | grep -E '(LogRecord|Body|trace_id)'"
echo ""
echo "2️⃣ Verificar que Tempo está recibiendo datos:"
echo "   kubectl logs -l app=tempo -c tempo --tail=20 | grep -i 'distributor'"
echo ""
echo "3️⃣ Ver trazas en Grafana:"
echo "   - Abre: http://localhost:3000"
echo "   - Ve al dashboard: 'Observability Stack - Overview'"
echo "   - Revisa los paneles de 'Distributed Traces'"
echo ""
echo "4️⃣ Ver trazas directamente en Tempo (si haces port-forward):"
echo "   kubectl port-forward svc/tempo 3200:3200"
echo "   Abre: http://localhost:3200"
echo ""
echo "5️⃣ Buscar trazas específicas en Tempo:"
echo "   Query: { resource.service.name = \"api-gateway\" }"
echo ""
