#!/bin/bash
set -e

# Función para eliminar inyecciones de Linkerd
remove_linkerd_injections() {
    echo "Eliminando inyecciones de Linkerd de los pods existentes..."
    kubectl delete deployment --all -n default || true
    
    # Esperar a que los pods se eliminen
    while kubectl get pods -n default 2>/dev/null | grep -q Running; do
        echo "Esperando que se eliminen los pods..."
        sleep 5
    done
}

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
    remove_linkerd_injections
    
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
kubectl delete deployments,services,configmaps -l app=jaeger --ignore-not-found
kubectl delete deployments,services,configmaps -l app=loki --ignore-not-found
kubectl delete deployments,services,configmaps -l app=opentelemetry-collector --ignore-not-found
kubectl delete deployments,services,configmaps -l app=grafana --ignore-not-found

# Esperar a que los recursos se limpien
sleep 10

# Desplegar componentes de observabilidad
echo "Desplegando componentes de observabilidad..."
deploy_with_linkerd "observability_kubernetes_base/deployment_jaeger.yaml" "jaeger"
deploy_with_linkerd "observability_kubernetes_base/deployment_loki.yaml" "loki"
deploy_with_linkerd "observability_kubernetes_base/deployment_opentelemetry.yaml" "otel-collector"
deploy_with_linkerd "observability_kubernetes_base/deployment_grafana.yaml" "grafana"

# Esperar a que los componentes estén listos con reintentos
wait_for_pod_ready "app=jaeger" 120 || exit 1
wait_for_pod_ready "app=loki" 120 || exit 1
wait_for_pod_ready "app=opentelemetry-collector" 120 || exit 1
wait_for_pod_ready "app=grafana" 120 || exit 1

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
echo "URLs de acceso:"
echo "Grafana: $(minikube service grafana --url)"
echo "Jaeger: $(minikube service jaeger --url)"
