# 🔄 Flujo de Observabilidad: Aplicaciones → Collector → Tempo → Grafana

## 📊 Visión General del Flujo

```
┌─────────────────┐         ┌──────────────┐         ┌──────────┐         ┌─────────┐
│   Aplicaciones  │────────▶│   Collector  │────────▶│  Tempo   │◀────────│ Grafana │
│ (API Gateway,   │  OTLP   │ (OTLP)       │  OTLP   │ (OTLP)   │  HTTP   │ (UI)    │
│  micro-1,       │         │              │         │          │         │         │
│  micro-2)       │         │              │         │          │         │         │
└─────────────────┘         └──────────────┘         └──────────┘         └─────────┘
```

## 🔍 Detalles Técnicos de la Comunicación

### 1. Aplicaciones → Collector

**Protocolo:** OTLP (OpenTelemetry Protocol)
- **gRPC:** Puerto `4317`
- **HTTP:** Puerto `4318`

**DNS:** Las aplicaciones envían datos al collector usando el DNS del Service de Kubernetes:
- `otel-collector:4317` (gRPC para traces y métricas)
- `otel-collector:4318` (HTTP para logs)

**Configuración en las aplicaciones:**
- API Gateway (Node.js): `http://otel-collector:4318/v1/logs`, `/v1/traces`, `/v1/metrics`
- micro-1 (Rust): `http://otel-collector:4317` (gRPC)
- micro-2 (Go): `otel-collector:4317` (gRPC)

**Dentro del pod del collector:**
- El collector escucha en `0.0.0.0:4317` y `0.0.0.0:4318`
- `0.0.0.0` significa "escuchar en todas las interfaces de red dentro del pod"
- El Service de Kubernetes (`otel-collector`) enruta el tráfico desde otros pods al pod del collector

### 2. Collector → Tempo

**Protocolo:** OTLP
- **gRPC:** Puerto `4317` (para traces)
- **HTTP:** Puerto `4318` (para logs)

**DNS:** El collector envía datos a Tempo usando el DNS del Service de Kubernetes:
- `tempo:4317` (gRPC para traces) - **IMPORTANTE:** Sin prefijo `http://` porque es gRPC
- `http://tempo:4318` (HTTP para logs) - **IMPORTANTE:** Con prefijo `http://` porque es HTTP

**Configuración en el collector:**
```yaml
exporters:
  otlp/tempo:
    endpoint: "tempo:4317"  # gRPC, sin http://
    tls:
      insecure: true
  otlp/tempo-http:
    endpoint: "http://tempo:4318"  # HTTP, con http://
    tls:
      insecure: true
```

**Dentro del pod de Tempo:**
- Tempo escucha en `0.0.0.0:4317` (gRPC) y `0.0.0.0:4318` (HTTP)
- El Service de Kubernetes (`tempo`) enruta el tráfico desde el collector al pod de Tempo

### 3. Grafana → Tempo

**Protocolo:** HTTP

**DNS:** Grafana consulta datos de Tempo usando el DNS del Service de Kubernetes:
- `http://tempo:3200` (HTTP API de Tempo)

**Configuración en Grafana:**
```yaml
datasources:
  - name: Tempo
    type: tempo
    url: http://tempo:3200
```

## 🌐 Cómo Funciona el DNS de Kubernetes

Cuando una aplicación usa `otel-collector:4317`, Kubernetes:

1. **Resuelve el DNS:** Busca el Service llamado `otel-collector` en el mismo namespace
2. **Obtiene la IP del Service:** El Service tiene una IP virtual (ClusterIP), por ejemplo `10.96.0.100`
3. **Enruta el tráfico:** Kubernetes enruta el tráfico desde el pod de origen al pod destino usando la IP del Service
4. **Service Selector:** El Service usa un `selector` para encontrar los pods que coinciden con las etiquetas (`app: opentelemetry-collector`)
5. **Target Port:** El Service enruta el tráfico al `targetPort` del pod (en este caso, `4317`)

**Ejemplo de Service:**
```yaml
apiVersion: v1
kind: Service
metadata:
  name: otel-collector
spec:
  ports:
  - port: 4317          # Puerto del Service (lo que usan otros pods)
    targetPort: 4317    # Puerto del pod (donde escucha el collector)
  selector:
    app: opentelemetry-collector  # Etiquetas que deben coincidir
```

## 🔗 Integración con Linkerd

### ¿Cómo funciona Linkerd con OpenTelemetry?

Linkerd tiene integración nativa con OpenTelemetry, pero funciona de dos maneras:

1. **Telemetría de Linkerd (automática):**
   - Linkerd puede enviar su propia telemetría (métricas de latencia, throughput, errores, etc.) a un collector de OpenTelemetry
   - Esto se configura a nivel del cluster, no por aplicación
   - Linkerd envía métricas sobre el tráfico que pasa por sus proxies

2. **Telemetría de aplicaciones (nuestra configuración):**
   - Nuestras aplicaciones (API Gateway, micro-1, micro-2) envían directamente su telemetría al collector
   - Linkerd NO intercepta este tráfico porque está configurado para no hacerlo

### ¿Por qué necesitamos las anotaciones de Linkerd?

```yaml
annotations:
  config.linkerd.io/skip-outbound-ports: "4317,4318"
```

Esta anotación le dice a Linkerd:
- **NO interceptes el tráfico** hacia los puertos `4317` y `4318`
- **NO apliques mTLS** a este tráfico
- **NO envíes métricas** de este tráfico a Linkerd

**¿Por qué?**
- El tráfico OTLP (OpenTelemetry Protocol) ya está encriptado/estructurado
- No queremos que Linkerd interfiera con la comunicación entre aplicaciones y el collector
- Evitamos problemas de certificados TLS y doble encriptación

### ¿Dónde aplicamos estas anotaciones?

1. **En el collector:**
   ```yaml
   annotations:
     config.linkerd.io/skip-outbound-ports: "4317,3100"
   ```
   - `4317`: Puerto para enviar traces a Tempo (gRPC)
   - `3100`: Puerto para enviar logs a Loki (si se usara, pero ahora usamos Tempo)

2. **En Tempo:**
   ```yaml
   annotations:
     config.linkerd.io/skip-outbound-ports: "4317,4318"
   ```
   - `4317`: Puerto para recibir traces del collector (gRPC)
   - `4318`: Puerto para recibir logs del collector (HTTP)

3. **En las aplicaciones (micro-1, micro-2):**
   ```yaml
   annotations:
     config.linkerd.io/opaque-ports: "4317"
   ```
   - Esto marca el puerto `4317` como "opaco", lo que significa que Linkerd no intenta inspeccionar el tráfico

## 🔄 Flujo Completo Paso a Paso

### 1. Aplicación genera un log/trace:

**API Gateway (Node.js):**
```typescript
const logger = logs.getLoggerProvider().getLogger('api-gateway', '1.0.0');
logger.emit({
  severityNumber: SeverityNumber.INFO,
  body: "Request received",
  attributes: { trace_id: "...", span_id: "..." }
});
```

### 2. SDK de OpenTelemetry envía al collector:

**DNS Resolución:**
- La aplicación resuelve `otel-collector` → IP del Service (ej: `10.96.0.100`)
- Envía HTTP POST a `http://10.96.0.100:4318/v1/logs`

**Dentro del cluster:**
- Kubernetes enruta el tráfico al pod del collector
- El pod del collector recibe en `0.0.0.0:4318`

### 3. Collector procesa y envía a Tempo:

**Procesamiento:**
- El collector recibe el log en el receiver `otlp`
- Pasa por los processors: `batch`, `memory_limiter`, `resource`
- El exporter `otlp/tempo-http` envía a Tempo

**Envío a Tempo:**
- DNS: `tempo` → IP del Service de Tempo (ej: `10.96.0.150`)
- HTTP POST a `http://10.96.0.150:4318/v1/logs`

**Dentro del pod de Tempo:**
- Tempo recibe en `0.0.0.0:4318`
- Almacena el log en su storage local (`/var/tempo/traces`)

### 4. Grafana consulta Tempo:

**Consulta:**
- Grafana resuelve `tempo` → IP del Service de Tempo
- HTTP GET a `http://10.96.0.150:3200/api/traces/{trace_id}`

**Dentro del pod de Tempo:**
- Tempo responde con los datos solicitados
- Grafana muestra los logs/traces en la UI

## ✅ Checklist de Verificación

Para verificar que todo está funcionando correctamente:

1. **Verificar que los Services existen:**
   ```bash
   kubectl get svc otel-collector tempo
   ```

2. **Verificar que los pods están corriendo:**
   ```bash
   kubectl get pods -l app=opentelemetry-collector
   kubectl get pods -l app=tempo
   ```

3. **Verificar conectividad desde el collector a Tempo:**
   ```bash
   kubectl exec -it <collector-pod> -- wget -O- http://tempo:4318
   ```

4. **Verificar logs del collector:**
   ```bash
   kubectl logs -l app=opentelemetry-collector | grep -i tempo
   ```

5. **Verificar logs de Tempo:**
   ```bash
   kubectl logs -l app=tempo -c tempo | grep -i "distributor\|received"
   ```

6. **Generar tráfico de prueba:**
   ```bash
   curl http://localhost:8080/weather/micro2?city=London
   ```

7. **Verificar en Grafana:**
   - Abrir Grafana: `http://localhost:3000`
   - Ir a "Explore" → Seleccionar "Tempo"
   - Buscar traces por `service.name="api-gateway"`

## 🐛 Troubleshooting Común

### Problema: "Cannot connect to tempo:4317"

**Posibles causas:**
1. El Service de Tempo no existe: `kubectl get svc tempo`
2. Los pods de Tempo no están corriendo: `kubectl get pods -l app=tempo`
3. La configuración del exporter está mal: Verificar que `otlp/tempo` use `tempo:4317` (sin `http://`)
4. Linkerd está interceptando el tráfico: Verificar anotaciones `config.linkerd.io/skip-outbound-ports`

### Problema: "No logs/traces in Grafana"

**Posibles causas:**
1. Los logs/traces no están llegando al collector: Verificar logs del collector
2. El collector no está enviando a Tempo: Verificar logs del collector con `grep -i tempo`
3. Tempo no está recibiendo datos: Verificar logs de Tempo
4. Grafana no está configurada correctamente: Verificar datasource de Tempo en Grafana

### Problema: "DNS resolution failed"

**Posibles causas:**
1. Los Services no están en el mismo namespace: Verificar con `kubectl get svc -A`
2. El DNS de Kubernetes no está funcionando: Verificar con `nslookup otel-collector` desde un pod

## 📚 Referencias

- [OpenTelemetry Collector Documentation](https://opentelemetry.io/docs/collector/)
- [Grafana Tempo Documentation](https://grafana.com/docs/tempo/latest/)
- [Kubernetes Services Documentation](https://kubernetes.io/docs/concepts/services-networking/service/)
- [Linkerd OpenTelemetry Integration](https://linkerd.io/2/tasks/observability/opentelemetry/)
