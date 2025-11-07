#!/bin/bash
set -e

# Script para gestionar port-forwards de los servicios
# Uso: ./scripts/port-forward.sh [start|stop|status]

cd "$(dirname "$0")/.."

ACTION=${1:-start}

kill_port_forward() {
    local port=$1
    local pids=$(lsof -ti :$port 2>/dev/null || true)
    if [ -n "$pids" ]; then
        echo "🛑 Matando procesos en puerto $port..."
        echo "$pids" | xargs kill -9 2>/dev/null || true
        sleep 1
    fi
}

start_port_forward() {
    local service=$1
    local local_port=$2
    local remote_port=$3
    
    if lsof -i :$local_port > /dev/null 2>&1; then
        echo "⚠️  Puerto $local_port ya está en uso. Matando proceso anterior..."
        kill_port_forward $local_port
    fi
    
    echo "🚀 Iniciando port-forward: $service ($local_port:$remote_port)"
    kubectl port-forward svc/$service $local_port:$remote_port > /dev/null 2>&1 &
    sleep 1
    
    if lsof -i :$local_port > /dev/null 2>&1; then
        echo "✅ Port-forward de $service iniciado en puerto $local_port"
    else
        echo "❌ Error al iniciar port-forward de $service"
        return 1
    fi
}

case $ACTION in
    start)
        echo "🚀 Iniciando port-forwards para todos los servicios..."
        echo ""
        start_port_forward "grafana" 3000 3000
        start_port_forward "jaeger" 16686 16686
        start_port_forward "prometheus" 9090 9090
        start_port_forward "alertmanager" 9093 9093
        start_port_forward "api-gateway" 8080 3000
        start_port_forward "otel-collector" 8889 8889
        
        echo "🚀 Iniciando port-forward: Linkerd Viz (8084:8084)"
        kubectl -n linkerd-viz port-forward svc/web 8084:8084 > /dev/null 2>&1 &
        sleep 1
        if lsof -i :8084 > /dev/null 2>&1; then
            echo "✅ Port-forward de Linkerd Viz iniciado en puerto 8084"
        else
            echo "❌ Error al iniciar port-forward de Linkerd Viz"
        fi
        
        echo ""
        echo "✅ Todos los port-forwards iniciados"
        echo ""
        echo "🌐 URLs de acceso:"
        echo "   Grafana: http://localhost:3000"
        echo "   Jaeger: http://localhost:16686"
        echo "   Prometheus: http://localhost:9090"
        echo "   AlertManager: http://localhost:9093"
        echo "   API Gateway: http://localhost:8080"
        echo "   OpenTelemetry Collector: http://localhost:8889"
        echo "   Linkerd Viz: http://localhost:8084"
        echo ""
        echo "💡 Para detener todos los port-forwards: ./scripts/port-forward.sh stop"
        ;;
    
    stop)
        echo "🛑 Deteniendo todos los port-forwards..."
        echo ""
        kill_port_forward 3000
        kill_port_forward 16686
        kill_port_forward 9090
        kill_port_forward 9093
        kill_port_forward 8080
        kill_port_forward 8889
        kill_port_forward 8084
        
        pkill -f "kubectl port-forward" 2>/dev/null || true
        sleep 1
        
        echo "✅ Todos los port-forwards detenidos"
        ;;
    
    status)
        echo "📊 Estado de los port-forwards:"
        echo ""
        ports=(3000 16686 9090 9093 8080 8889 8084)
        services=("grafana" "jaeger" "prometheus" "alertmanager" "api-gateway" "otel-collector" "linkerd-viz")
        
        for i in "${!ports[@]}"; do
            port=${ports[$i]}
            service=${services[$i]}
            if lsof -i :$port > /dev/null 2>&1; then
                pid=$(lsof -ti :$port | head -1)
                echo "✅ $service (puerto $port) - PID: $pid"
            else
                echo "❌ $service (puerto $port) - No activo"
            fi
        done
        ;;
    
    restart)
        echo "🔄 Reiniciando port-forwards..."
        $0 stop
        sleep 2
        $0 start
        ;;
    
    *)
        echo "Uso: $0 [start|stop|status|restart]"
        echo ""
        echo "Comandos:"
        echo "  start   - Inicia todos los port-forwards"
        echo "  stop    - Detiene todos los port-forwards"
        echo "  status  - Muestra el estado de los port-forwards"
        echo "  restart - Reinicia todos los port-forwards"
        exit 1
        ;;
esac