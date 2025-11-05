#!/bin/bash

# Script para pruebas de stress y validación de observabilidad
# Este script generará diferentes tipos de carga de trabajo para validar
# el comportamiento de los microservicios y la observabilidad

set -e

API_GATEWAY_URL="http://localhost/api-gateway"
TOTAL_REQUESTS=1000
CONCURRENT_REQUESTS=20
DURATION=300  # 5 minutos

echo "=== LAB OBSERVABILITY STRESS TESTING ==="
echo "Iniciando pruebas de stress y validación..."
echo "Duración: ${DURATION} segundos"
echo "Requests totales: ${TOTAL_REQUESTS}"
echo "Concurrencia: ${CONCURRENT_REQUESTS}"
echo "======================================="

# Función para hacer requests asincrónos
make_request() {
    local endpoint=$1
    local request_num=$2
    
    response=$(curl -s -w "%{http_code};%{time_total}" -o /dev/null "${API_GATEWAY_URL}${endpoint}" || echo "000;0.0")
    http_code=$(echo $response | cut -d';' -f1)
    time_total=$(echo $response | cut -d';' -f2)
    
    echo "$(date '+%Y-%m-%d %H:%M:%S'),$request_num,$endpoint,$http_code,$time_total"
}

# Función para validar que los servicios están funcionando
validate_services() {
    echo "🔍 Validando servicios disponibles..."
    
    local services_ok=0
    
    # Test ping endpoint
    if curl -s -f "${API_GATEWAY_URL}/ping" > /dev/null 2>&1; then
        echo "✅ Ping endpoint OK"
        ((services_ok++))
    else
        echo "❌ Ping endpoint FAIL"
    fi
    
    # Test health endpoint
    if curl -s -f "${API_GATEWAY_URL}/health" > /dev/null 2>&1; then
        echo "✅ Health endpoint OK"
        ((services_ok++))
    else
        echo "❌ Health endpoint FAIL"
    fi
    
    # Test micro1 endpoint (puede fallar ocasionalmente)
    if curl -s "${API_GATEWAY_URL}/micro1" | grep -q "error" 2>/dev/null; then
        echo "⚠️  Micro1 endpoint con errores (esperado para testing)"
        ((services_ok++))
    else
        echo "✅ Micro1 endpoint OK"
        ((services_ok++))
    fi
    
    if [ $services_ok -eq 0 ]; then
        echo "❌ Ningún servicio disponible. Abortando pruebas."
        exit 1
    fi
    
    echo "🚀 Servicios validados. Iniciando pruebas de carga..."
}

# Crear directorio de resultados
mkdir -p results
RESULT_FILE="results/stress-test-$(date +%Y%m%d-%H%M%S).csv"
echo "timestamp,request_id,endpoint,http_code,response_time" > $RESULT_FILE

validate_services

echo "📊 Iniciando pruebas de carga..."

# Test 1: Ping endpoint (debería ser muy rápido y sin errores)
echo "🔨 Test 1: Ping endpoint stress test..."
for i in $(seq 1 200); do
    make_request "/ping" $i &
    if [ $((i % $CONCURRENT_REQUESTS)) -eq 0 ]; then
        wait
    fi
done >> $RESULT_FILE &

# Test 2: Endpoints de microservicios (pueden generar errores intencionalmente)
echo "🔨 Test 2: Microservices stress test..."
for i in $(seq 201 800); do
    endpoint_choice=$((RANDOM % 3))
    case $endpoint_choice in
        0) make_request "/micro1" $i & ;;
        1) make_request "/micro2" $i & ;;
        2) make_request "/ping" $i & ;;
    esac
    
    if [ $((i % $CONCURRENT_REQUESTS)) -eq 0 ]; then
        wait
    fi
done >> $RESULT_FILE &

# Test 3: Endpoints no encontrados (para generar errores 404)
echo "🔨 Test 3: 404 error test..."
for i in $(seq 801 1000); do
    make_request "/nonexistent-$i" $i &
    if [ $((i % $CONCURRENT_REQUESTS)) -eq 0 ]; then
        wait
    fi
done >> $RESULT_FILE &

# Esperar que terminen todos los tests
wait

echo "🏁 Pruebas completadas!"
echo "📈 Analizando resultados..."

# Análisis básico de resultados
total_requests=$(tail -n +2 $RESULT_FILE | wc -l)
success_requests=$(tail -n +2 $RESULT_FILE | cut -d',' -f4 | grep -E '^2[0-9][0-9]$' | wc -l)
error_requests=$(tail -n +2 $RESULT_FILE | cut -d',' -f4 | grep -E '^[45][0-9][0-9]$' | wc -l)

echo "======================================="
echo "📊 RESUMEN DE PRUEBAS DE STRESS:"
echo "Total requests: $total_requests"
echo "Requests exitosos: $success_requests"
echo "Requests con error: $error_requests"
echo "Tasa de éxito: $(echo "scale=2; $success_requests * 100 / $total_requests" | bc)%"
echo "======================================="

# Generar métricas por endpoint
echo "📈 MÉTRICAS POR ENDPOINT:"
echo "Endpoint | Total | Éxitos | Errores | Tasa de éxito"
echo "---------|-------|--------|---------|---------------"

for endpoint in "/ping" "/micro1" "/micro2"; do
    endpoint_data=$(grep ",${endpoint}," $RESULT_FILE | tail -n +2)
    if [ ! -z "$endpoint_data" ]; then
        endpoint_total=$(echo "$endpoint_data" | wc -l)
        endpoint_success=$(echo "$endpoint_data" | cut -d',' -f4 | grep -E '^2[0-9][0-9]$' | wc -l)
        endpoint_errors=$((endpoint_total - endpoint_success))
        if [ $endpoint_total -gt 0 ]; then
            success_rate=$(echo "scale=1; $endpoint_success * 100 / $endpoint_total" | bc)
            printf "%-9s | %5d | %6d | %7d | %s%%\n" "$endpoint" $endpoint_total $endpoint_success $endpoint_errors $success_rate
        fi
    fi
done

echo ""
echo "💾 Resultados guardados en: $RESULT_FILE"
echo ""
echo "🔍 PRÓXIMOS PASOS PARA ANÁLISIS:"
echo "1. Revisar trazas en Jaeger: http://localhost/jaeger"
echo "2. Verificar métricas en Prometheus: http://localhost/prometheus"
echo "3. Analizar dashboards en Grafana: http://localhost/grafana"
echo "4. Comprobar alertas en AlertManager: http://localhost/alertmanager"
echo "5. Revisar logs en Loki: http://localhost/loki"
echo ""
echo "🎯 Buscar en observabilidad:"
echo "- Tiempo de respuesta alto"
echo "- Tasa de error elevada"
echo "- Trazas con errores"
echo "- Alertas activadas"
echo "- Patrones de uso anómalos"
