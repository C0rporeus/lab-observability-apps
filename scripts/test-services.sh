#!/bin/bash

# Script simple para probar los servicios y validar que funcionan correctamente
# después de las mejoras de robustez

set -e

echo "=== LAB OBSERVABILITY SERVICES VALIDATION ==="

# URLs base - ajustar según deployment
API_GATEWAY_URL=${API_GATEWAY_URL:-"http://localhost:3000"}
MICRO1_URL=${MICRO1_URL:-"micro-1:50051"}
MICRO2_URL=${MICRO2_URL:-"micro-2:50051"}

echo "Testing API Gateway at: $API_GATEWAY_URL"

# Función para hacer requests con retry
test_endpoint() {
    local endpoint=$1
    local expected_status=${2:-200}
    local retries=3
    local delay=2
    
    for i in $(seq 1 $retries); do
        echo "Testing $endpoint (attempt $i/$retries)..."
        
        response=$(curl -s -w "\n%{http_code}" "${API_GATEWAY_URL}${endpoint}" || echo -e "\n000")
        http_code=$(echo "$response" | tail -n1)
        body=$(echo "$response" | head -n -1)
        
        if [ "$http_code" = "$expected_status" ]; then
            echo "✅ $endpoint - Status: $http_code"
            echo "   Response: $(echo $body | head -c 100)..."
            return 0
        else
            echo "⚠️  $endpoint - Status: $http_code (expected: $expected_status)"
            if [ $i -lt $retries ]; then
                echo "   Retrying in ${delay}s..."
                sleep $delay
            fi
        fi
    done
    
    echo "❌ $endpoint - Failed after $retries attempts"
    return 1
}

# Función para test de stress básico
stress_test() {
    local endpoint=$1
    local requests=$2
    
    echo "🔥 Stress testing $endpoint with $requests requests..."
    
    start_time=$(date +%s)
    for i in $(seq 1 $requests); do
        curl -s "${API_GATEWAY_URL}${endpoint}" > /dev/null &
        
        # Limitar concurrencia
        if [ $(($i % 10)) -eq 0 ]; then
            wait
        fi
    done
    wait
    end_time=$(date +%s)
    
    duration=$((end_time - start_time))
    echo "   Completed $requests requests in ${duration}s"
}

echo ""
echo "🔍 BASIC SERVICE TESTS"
echo "======================"

# Test 1: Ping endpoint (debería funcionar siempre)
test_endpoint "/ping" 200

# Test 2: Health endpoint (nuevo endpoint)
test_endpoint "/health" 200

# Test 3: Micro1 endpoint (puede fallar ocasionalmente)
test_endpoint "/micro1" 200 || test_endpoint "/micro1" 500 || test_endpoint "/micro1" 503

# Test 4: Micro2 endpoint (puede fallar ocasionalmente)
test_endpoint "/micro2" 200 || test_endpoint "/micro2" 500 || test_endpoint "/micro2" 503

# Test 5: 404 endpoint
test_endpoint "/nonexistent" 404

echo ""
echo "🔬 ERROR HANDLING TESTS"
echo "======================="

# Test de endpoints que pueden generar errores
echo "Testing error scenarios..."

# Llamadas múltiples para generar algunos errores y ver recuperación
for i in $(seq 1 5); do
    echo "Round $i of error handling test..."
    
    # Hacer varias llamadas concurrentes
    test_endpoint "/micro1" 200 &
    test_endpoint "/micro2" 200 &
    test_endpoint "/ping" 200 &
    test_endpoint "/health" 200 &
    wait
    
    sleep 1
done

echo ""
echo "⚡ PERFORMANCE TESTS"
echo "==================="

# Test básico de rendimiento
stress_test "/ping" 50

echo ""
echo "📊 VALIDATION SUMMARY"
echo "===================="

echo "✅ Basic functionality tests completed"
echo "✅ Error handling validation completed"  
echo "✅ Performance tests completed"
echo ""
echo "🔍 Next steps for observability analysis:"
echo "1. Check Jaeger traces for request flows and error patterns"
echo "2. Review Prometheus metrics for success/error rates"
echo "3. Examine Grafana dashboards for performance trends"
echo "4. Verify AlertManager rules are triggered appropriately"
echo "5. Analyze Loki logs for error details and patterns"
echo ""
echo "🎯 Key things to observe:"
echo "- Request tracing across microservices"
echo "- Error propagation and recovery"
echo "- Performance metrics under load"
echo "- Alert triggering and resolution"
echo "- Service health and availability patterns"
