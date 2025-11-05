#!/bin/bash
set -e

cd "$(dirname "$0")/.."

# Función para generar certificados de Linkerd válidos
generate_linkerd_certs() {
    echo "Generando certificados para Linkerd..."
    
    # Generar el certificado raíz
    step certificate create root.linkerd.cluster.local ca.crt ca.key \
        --profile root-ca --no-password --insecure \
        --force \
        --not-before=-5m --not-after=24h

    # Generar el certificado del emisor
    step certificate create identity.linkerd.cluster.local issuer.crt issuer.key \
        --profile intermediate-ca --no-password --insecure \
        --force \
        --ca ca.crt --ca-key ca.key \
        --not-before=-5m --not-after=24h
}

# Función para limpiar Linkerd
clean_linkerd() {
    echo "Limpiando instalación previa de Linkerd..."
    
    # Intentar desinstalar Linkerd
    linkerd uninstall | kubectl delete -f - || true
    kubectl delete namespace linkerd --force --grace-period=0 2>/dev/null || true
    
    # Esperar a que se elimine el namespace
    while kubectl get namespace linkerd >/dev/null 2>&1; do
        echo "Esperando que se elimine el namespace linkerd..."
        sleep 5
    done
    
    echo "Linkerd eliminado completamente"
}

# Función para esperar a que un pod esté completamente listo y estable
wait_for_pod_ready() {
    local label=$1
    local timeout=$2
    local retries=3
    local retry_count=0

    echo "Esperando a que los pods con label $label estén listos..."
    while [ $retry_count -lt $retries ]; do
        if kubectl wait --for=condition=ready pod -l $label --timeout=${timeout}s; then
            # Verificar si el pod está realmente estable (sin reinicios recientes)
            if ! kubectl get pods -l $label | grep -q "CrashLoopBackOff\|Error\|PostStartHookError"; then
                echo "Pod $label está estable y funcionando"
                return 0
            fi
        fi
        
        echo "Reintentando despliegue de $label..."
        kubectl rollout restart deployment -l $label
        sleep 10
        ((retry_count++))
    done

    echo "Error: No se pudo estabilizar $label después de $retries intentos"
    return 1
}

# Función para aplicar deployment con inyección de Linkerd
deploy_with_linkerd() {
    local file=$1
    local name=$2
    
    echo "Desplegando $name..."
    kubectl apply -f "$file"
    
    # Esperar un momento para que el deployment se cree
    sleep 5
    
    # Inyectar Linkerd y reaplica
    kubectl get deployments.apps $name -o yaml | linkerd inject - | kubectl apply -f -
}

# Limpiar y reinstalar Linkerd
echo "Iniciando reinstalación de Linkerd..."
clean_linkerd

# Generar nuevos certificados
echo "Generando nuevos certificados..."
generate_linkerd_certs

echo "Instalando Linkerd nuevo..."
# Instalar CRDs primero
linkerd install --crds | kubectl apply -f -

# Instalar Linkerd con los nuevos certificados
linkerd install \
    --identity-trust-anchors-file ca.crt \
    --identity-issuer-certificate-file issuer.crt \
    --identity-issuer-key-file issuer.key \
    --set proxyInit.runAsRoot=true | kubectl apply -f -

# Esperar a que Linkerd esté listo
echo "Esperando a que Linkerd esté listo..."
kubectl wait --for=condition=ready pod -l linkerd.io/control-plane-ns=linkerd -n linkerd --timeout=300s

# Verificar la instalación
echo "Verificando la instalación de Linkerd..."
linkerd check

# Limpiar recursos existentes
echo "Limpiando recursos previos..."
kubectl delete deployments,services,configmaps -l app=opentelemetry-collector --ignore-not-found
kubectl delete deployments,services,configmaps -l app=grafana --ignore-not-found
kubectl delete deployments,services,configmaps -l app=prometheus --ignore-not-found
kubectl delete deployments,services,configmaps -l app=alertmanager --ignore-not-found
kubectl delete deployments,services,configmaps -l app=tempo --ignore-not-found
kubectl delete daemonset promtail --ignore-not-found
kubectl delete horizontalpodautoscalers --all --ignore-not-found
kubectl delete poddisruptionbudgets --all --ignore-not-found

# Esperar a que los recursos se limpien
sleep 10

# Desplegar componentes de observabilidad
echo "Desplegando componentes de observabilidad..."
deploy_with_linkerd "observability_kubernetes_base/deployment_tempo.yaml" "tempo"
deploy_with_linkerd "observability_kubernetes_base/deployment_opentelemetry.yaml" "otel-collector"
deploy_with_linkerd "observability_kubernetes_base/deployment_prometheus.yaml" "prometheus"
kubectl apply -f "observability_kubernetes_base/prometheus-rules.yaml"
deploy_with_linkerd "observability_kubernetes_base/deployment_alertmanager.yaml" "alertmanager"
deploy_with_linkerd "observability_kubernetes_base/deployment_grafana.yaml" "grafana"
kubectl apply -f "observability_kubernetes_base/grafana-dashboards.yaml"

# Esperar a que los componentes estén listos con reintentos
wait_for_pod_ready "app=tempo" 120 || exit 1
wait_for_pod_ready "app=opentelemetry-collector" 120 || exit 1
wait_for_pod_ready "app=prometheus" 120 || exit 1
wait_for_pod_ready "app=alertmanager" 120 || exit 1
wait_for_pod_ready "app=grafana" 120 || exit 1

# Crear secret de Weather API Key desde archivo .env (si existe)
echo "Creando secret de Weather API Key..."
if [ -f ".env" ]; then
    ./scripts/create-secrets.sh
else
    echo "⚠️  No se encontró archivo .env para Weather API Key."
    echo "💡 Para configurar la API key, crea un archivo .env basado en env.example"
    echo "⚠️  Los microservicios fallarán sin una API key válida de OpenWeatherMap"
fi

# Desplegar PostgreSQL
echo "Desplegando PostgreSQL..."
kubectl apply -f "postgres-deployment.yaml"

# Esperar a que PostgreSQL esté listo
wait_for_pod_ready "app=postgres" 120 || exit 1

# Desplegar microservicios
echo "Desplegando microservicios..."
deploy_with_linkerd "micro-1/deployment.yaml" "micro-1-deployment"
deploy_with_linkerd "micro-2/deployment.yaml" "micro-2-deployment"
deploy_with_linkerd "micro-3/deployment.yaml" "api-gateway"

# Esperar a que los microservicios estén listos
wait_for_pod_ready "app=micro-1" 120 || exit 1
wait_for_pod_ready "app=micro-2" 120 || exit 1
wait_for_pod_ready "app=api-gateway" 120 || exit 1

echo "Laboratorio desplegado correctamente!"
echo ""
echo "🌐 URLs de acceso:"

# Detectar si estamos usando minikube o Docker Desktop
if command -v minikube > /dev/null 2>&1 && minikube status > /dev/null 2>&1; then
    # Usando minikube
    echo "Grafana: $(minikube service grafana --url 2>/dev/null || echo 'http://localhost:3000')"
    echo "Tempo: $(minikube service tempo --url 2>/dev/null || echo 'http://localhost:3200')"
    echo "Prometheus: $(minikube service prometheus --url 2>/dev/null || echo 'http://localhost:9090')"
    echo "AlertManager: $(minikube service alertmanager --url 2>/dev/null || echo 'http://localhost:9093')"
    echo ""
    echo "💡 Para acceder a los servicios, ejecuta:"
    echo "   minikube service grafana"
    echo "   minikube service tempo"
    echo "   minikube service prometheus"
    echo "   minikube service alertmanager"
else
    # Usando Docker Desktop Kubernetes o otro entorno
    echo "   Grafana: http://localhost:3000"
    echo "   Tempo: http://localhost:3200"
    echo "   Prometheus: http://localhost:9090"
    echo "   AlertManager: http://localhost:9093"
    echo "   API Gateway: http://localhost:8080"
    echo ""
    echo "💡 Para acceder a los servicios, ejecuta en terminales separadas:"
    echo "   kubectl port-forward svc/grafana 3000:3000"
    echo "   kubectl port-forward svc/tempo 3200:3200"
    echo "   kubectl port-forward svc/prometheus 9090:9090"
    echo "   kubectl port-forward svc/alertmanager 9093:9093"
    echo "   kubectl port-forward svc/api-gateway 8080:3000"
fi
