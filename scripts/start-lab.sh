#!/bin/bash
set -e

echo "🚀 Iniciando laboratorio de observabilidad..."

# 1. Verificar que Docker Desktop está corriendo
echo "📦 Verificando Docker Desktop..."
if ! docker ps > /dev/null 2>&1; then
    echo "❌ Docker Desktop no está corriendo. Por favor inícialo primero."
    exit 1
fi
echo "✅ Docker Desktop funcionando"

# 2. Verificar Kubernetes (minikube o Docker Desktop)
echo "📦 Verificando Kubernetes..."
if command -v minikube > /dev/null 2>&1 && minikube status > /dev/null 2>&1; then
    echo "✅ minikube funcionando"
    USE_MINIKUBE=true
elif kubectl cluster-info > /dev/null 2>&1; then
    echo "✅ Kubernetes funcionando (Docker Desktop o otro entorno)"
    USE_MINIKUBE=false
else
    echo "❌ Kubernetes no está disponible"
    echo "💡 Inicia minikube con 'minikube start' o habilita Kubernetes en Docker Desktop"
    exit 1
fi

# 3. Verificar que Linkerd está instalado
echo "🔐 Verificando Linkerd..."
if ! kubectl get namespace linkerd > /dev/null 2>&1 || ! kubectl get pods -n linkerd 2>/dev/null | grep -q Running; then
    echo "⚠️  Linkerd no está instalado o no funcionando."
    echo "💡 Ejecuta './scripts/deploy-lab.sh' para una instalación completa"
    exit 1
fi
echo "✅ Linkerd funcionando"

# 4. Verificar certificados
echo "🔐 Verificando certificados de Linkerd..."
cd "$(dirname "$0")"
if [ ! -f "ca.crt" ] || [ ! -f "issuer.crt" ] || [ ! -f "issuer.key" ]; then
    echo "⚠️  Certificados no encontrados. Generándolos..."
    
    # Generar certificados
    step certificate create root.linkerd.cluster.local ca.crt ca.key \
        --profile root-ca --no-password --insecure \
        --force \
        --not-before=-5m --not-after=720h
    
    step certificate create identity.linkerd.cluster.local issuer.crt issuer.key \
        --profile intermediate-ca --no-password --insecure \
        --force \
        --ca ca.crt --ca-key ca.key \
        --not-before=-5m --not-after=720h
    
    echo "✅ Certificados generados"
fi

# 5. Verificar expiración de certificados (renovar si expiran en menos de 24h)
echo "🔍 Verificando validez de certificados..."
if command -v openssl > /dev/null 2>&1; then
    CERT_EXPIRY=$(openssl x509 -enddate -noout -in ca.crt | cut -d= -f2)
    CERT_EXPIRY_EPOCH=$(date -j -f "%b %d %H:%M:%S %Y %Z" "$CERT_EXPIRY" +%s 2>/dev/null || date -d "$CERT_EXPIRY" +%s)
    NOW_EPOCH=$(date +%s)
    HOURS_UNTIL_EXPIRY=$(( ($CERT_EXPIRY_EPOCH - $NOW_EPOCH) / 3600 ))
    
    if [ $HOURS_UNTIL_EXPIRY -lt 24 ]; then
        echo "⚠️  Los certificados expiran en menos de 24 horas. Regenerándolos..."
        
        step certificate create root.linkerd.cluster.local ca.crt ca.key \
            --profile root-ca --no-password --insecure \
            --force \
            --not-before=-5m --not-after=720h
        
        step certificate create identity.linkerd.cluster.local issuer.crt issuer.key \
            --profile intermediate-ca --no-password --insecure \
            --force \
            --ca ca.crt --ca-key ca.key \
            --not-before=-5m --not-after=720h
        
        echo "🔄 Reinstalando Linkerd con nuevos certificados..."
        linkerd uninstall | kubectl delete -f - || true
        linkerd install --crds | kubectl apply -f -
        linkerd install \
            --identity-trust-anchors-file ca.crt \
            --identity-issuer-certificate-file issuer.crt \
            --identity-issuer-key-file issuer.key \
            --set proxyInit.runAsRoot=true | kubectl apply -f -
        
        echo "⏳ Esperando que Linkerd esté listo..."
        kubectl wait --for=condition=ready pod -l linkerd.io/control-plane-ns=linkerd -n linkerd --timeout=300s
        
        echo "✅ Linkerd actualizado"
    else
        echo "✅ Certificados válidos por $HOURS_UNTIL_EXPIRY horas"
    fi
fi

# 6. Aplicar ConfigMap de prometheus-rules si no existe
echo "📊 Verificando configuración de Prometheus..."
if ! kubectl get configmap prometheus-rules > /dev/null 2>&1; then
    echo "📝 Creando prometheus-rules..."
    kubectl apply -f observability_kubernetes_base/prometheus-rules.yaml
fi

# 7. Desplegar todos los componentes si no existen
echo "🚀 Verificando deployments..."

# Observabilidad
for service in tempo otel-collector prometheus alertmanager grafana; do
    if ! kubectl get deployment $service > /dev/null 2>&1; then
        echo "📦 Desplegando $service..."
        kubectl apply -f observability_kubernetes_base/deployment_${service}.yaml
        kubectl get deployment $service -o yaml | linkerd inject - | kubectl apply -f -
    fi
done

# Verificar/Crear secret de Weather API Key (si no existe)
if ! kubectl get secret weather-api-key > /dev/null 2>&1; then
    echo "🔐 Creando secret de Weather API Key..."
    if [ -f ".env" ]; then
        ./scripts/create-secrets.sh
    else
        echo "⚠️  No se encontró archivo .env para Weather API Key."
        echo "💡 Para configurar la API key, crea un archivo .env basado en env.example"
        echo "⚠️  Los microservicios fallarán sin una API key válida de OpenWeatherMap"
    fi
fi

# PostgreSQL
if ! kubectl get deployment postgres-deployment > /dev/null 2>&1; then
    echo "📦 Desplegando PostgreSQL..."
    kubectl apply -f postgres-deployment.yaml
fi

# Microservicios
for micro in micro-1 micro-2 micro-3; do
    if ! kubectl get deployment ${micro}-deployment > /dev/null 2>&1; then
        echo "📦 Desplegando ${micro}..."
        if [ "$micro" = "micro-3" ]; then
            kubectl apply -f ${micro}/deployment.yaml
            kubectl get deployment api-gateway -o yaml | linkerd inject - | kubectl apply -f -
        else
            kubectl apply -f ${micro}/deployment.yaml
            kubectl get deployment ${micro}-deployment -o yaml | linkerd inject - | kubectl apply -f -
        fi
    fi
done

# 8. Esperar a que todos los pods estén listos
echo "⏳ Esperando que todos los pods estén listos..."
sleep 10

kubectl wait --for=condition=ready pod -l app=tempo --timeout=120s || echo "⚠️  Tempo tardando más de lo esperado"
kubectl wait --for=condition=ready pod -l app=opentelemetry-collector --timeout=120s || echo "⚠️  OpenTelemetry tardando más de lo esperado"
kubectl wait --for=condition=ready pod -l app=prometheus --timeout=120s || echo "⚠️  Prometheus tardando más de lo esperado"
kubectl wait --for=condition=ready pod -l app=alertmanager --timeout=120s || echo "⚠️  Alertmanager tardando más de lo esperado"
kubectl wait --for=condition=ready pod -l app=grafana --timeout=120s || echo "⚠️  Grafana tardando más de lo esperado"

kubectl wait --for=condition=ready pod -l app=micro-1 --timeout=120s || echo "⚠️  micro-1 tardando más de lo esperado"
kubectl wait --for=condition=ready pod -l app=micro-2 --timeout=120s || echo "⚠️  micro-2 tardando más de lo esperado"
kubectl wait --for=condition=ready pod -l app=api-gateway --timeout=120s || echo "⚠️  api-gateway tardando más de lo esperado"

# 9. Mostrar estado final
echo ""
echo "✅ Laboratorio iniciado correctamente!"
echo ""
echo "📊 Estado de los servicios:"
kubectl get pods | grep -E "Running|PENDING|ERROR"
echo ""
echo "🌐 URLs de acceso:"
echo "   Jaeger: http://localhost:16686 (ejecuta: kubectl port-forward svc/jaeger 16686:16686)"
echo "   Grafana: http://localhost:3000 (ejecuta: kubectl port-forward svc/grafana 3000:3000)"
echo "   Prometheus: http://localhost:9090 (ejecuta: kubectl port-forward svc/prometheus 9090:9090)"
echo "   API Gateway: http://localhost:8080 (ejecuta: kubectl port-forward svc/api-gateway 8080:3000)"
echo ""
echo "🔍 Para ver todos los pods: kubectl get pods"
echo "📝 Para ver logs: kubectl logs -l app=<nombre-servicio>"

