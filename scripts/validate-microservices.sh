#!/bin/bash

# Script para validar que las comunicaciones entre microservicios funcionen correctamente
# Verifica que el API Gateway pueda comunicarse con micro-1 y micro-2

set -e

echo "=== VALIDACIÓN DE COMUNICACIONES ENTRE MICROSERVICIOS ==="
echo "Verificando que las rutas y protocolos coincidan correctamente..."
echo ""

# Configuración
API_GATEWAY_URL=${API_GATEWAY_URL:-"http://localhost:3000"}
MAX_ATTEMPTS=5
WAIT_TIME=2

# Función para hacer requests con retry
make_request_with_retry() {
    local endpoint=$1
    local expected_status=${2:-200}
    local attempt=1
    
    while [ $attempt -le $MAX_ATTEMPTS ]; do
        echo "Intento $attempt/$MAX_ATTEMPTS para $endpoint..."
        
        response=$(curl -s -w "\n%{http_code}" "${API_GATEWAY_URL}${endpoint}" || echo -e "\n000")
        http_code=$(echo "$response" | tail -n1)
        body=$(echo "$response" | head -n -1)
        
        echo "  Status: $http_code"
        echo "  Response: $(echo $body | head -c 100)..."
        
        if [ "$http_code" = "$expected_status" ] || [ "$http_code" = "200" ]; then
            echo "  ✅ $endpoint - Comunicación exitosa"
            return 0
        else
            echo "  ⚠️  $endpoint - Status: $http_code (intento $attempt)"
            if [ $attempt -lt $MAX_ATTEMPTS ]; then
                echo "  Esperando ${WAIT_TIME}s antes del siguiente intento..."
                sleep $WAIT_TIME
            fi
        fi
        
        ((attempt++))
    done
    
    echo "  ❌ $endpoint - Falló después de $MAX_ATTEMPTS intentos"
    return 1
}

# Función para verificar que el contenido de la respuesta sea válido
validate_response_content() {
    local endpoint=$1
    local expected_pattern=$2
    
    response=$(curl -s "${API_GATEWAY_URL}${endpoint}")
    
    if echo "$response" | grep -q "$expected_pattern"; then
        echo "  ✅ $endpoint - Contenido de respuesta válido"
        return 0
    else
        echo "  ⚠️  $endpoint - Contenido inesperado"
        echo "  Respuesta: $(echo $response | head -c 200)..."
        return 1
    fi
}

echo "🔍 PASO 1: Verificar que el API Gateway esté funcionando"
echo "=================================================="
make_request_with_retry "/ping" 200
make_request_with_retry "/health" 200

echo ""
echo "🔍 PASO 2: Verificar comunicación con micro-1 (gRPC)"
echo "================================================"
echo "Probando endpoint /micro1 que debe comunicarse con micro-1 via gRPC..."

if make_request_with_retry "/micro1" 200; then
    echo "Verificando contenido de respuesta de micro-1..."
    validate_response_content "/micro1" "greeting"
else
    echo "❌ No se pudo comunicar con micro-1"
    echo "Esto podría indicar:"
    echo "  - micro-1 no está ejecutándose"
    echo "  - Problemas con el protocolo gRPC"
    echo "  - Método incorrecto (GetHelloWorld vs Ping)"
fi

echo ""
echo "🔍 PASO 3: Verificar comunicación con micro-2 (gRPC)"
echo "================================================"
echo "Probando endpoint /micro2 que debe comunicarse con micro-2 via gRPC..."

if make_request_with_retry "/micro2" 200; then
    echo "Verificando contenido de respuesta de micro-2..."
    validate_response_content "/micro2" "message"
else
    echo "❌ No se pudo comunicar con micro-2"
    echo "Esto podría indicar:"
    echo "  - micro-2 no tiene servidor gRPC implementado"
    echo "  - micro-2 no está ejecutándose en puerto 50051"
    echo "  - Problemas con el protocolo gRPC"
fi

echo ""
echo "🔍 PASO 4: Verificar manejo de errores"
echo "=================================="
echo "Probando endpoints que deberían generar errores controlados..."

# Test 404
make_request_with_retry "/nonexistent" 404

echo ""
echo "🔍 PASO 5: Verificar estabilidad bajo carga"
echo "======================================="
echo "Haciendo múltiples requests para verificar estabilidad..."

success_count=0
total_requests=10

for i in $(seq 1 $total_requests); do
    echo "Request $i/$total_requests..."
    if make_request_with_retry "/ping" 200 > /dev/null 2>&1; then
        ((success_count++))
    fi
done

success_rate=$((success_count * 100 / total_requests))
echo "Tasa de éxito: $success_count/$total_requests ($success_rate%)"

echo ""
echo "📊 RESUMEN DE VALIDACIÓN"
echo "======================="

# Verificar estado final de todos los servicios
echo "Estado de endpoints:"
curl -s "${API_GATEWAY_URL}/health" | jq -r '.status // "Error"' 2>/dev/null || echo "Health endpoint no disponible"

echo ""
echo "🔧 PROBLEMAS COMUNES Y SOLUCIONES:"
echo "================================="
echo "1. Si micro-1 falla:"
echo "   - Verificar que micro-1 esté usando el servicio 'Greeter'"
echo "   - Verificar que use métodos 'GetHelloWorld' y 'SendMessage'"
echo "   - Comprobar que esté escuchando en puerto 50051"

echo ""
echo "2. Si micro-2 falla:"
echo "   - Verificar que micro-2 tenga un servidor gRPC implementado"
echo "   - Verificar que responda al método 'Ping'"
echo "   - Comprobar que esté escuchando en puerto 50051"

echo ""
echo "3. Si el API Gateway falla:"
echo "   - Verificar que use los archivos protobuf correctos"
echo "   - micro-1: usar helloworld.proto con servicio Greeter"
echo "   - micro-2: usar micro.proto con servicio MicroService"

echo ""
echo "🎯 PRÓXIMOS PASOS:"
echo "=================="
echo "1. Revisar logs de cada microservicio"
echo "2. Verificar que los archivos .proto coincidan con la implementación"
echo "3. Probar con herramientas como grpcurl para debugging directo"
echo "4. Verificar conectividad de red entre servicios en Kubernetes"
