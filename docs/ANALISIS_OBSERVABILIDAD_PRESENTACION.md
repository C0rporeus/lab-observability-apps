# 📊 Análisis Profundo de Observabilidad e Instrumentación
## Laboratorio de Aplicaciones con Stack Completo de Observabilidad

**Documento de Análisis para Presentación**
*Insumo para Creación de Diapositivas, Infografías y Diagramas Explicativos*

---

## 📋 Tabla de Contenidos

1. [Visión General del Sistema](#1-visión-general-del-sistema)
2. [Arquitectura de Observabilidad](#2-arquitectura-de-observabilidad)
3. [Instrumentación Específica por Lenguaje](#3-instrumentación-específica-por-lenguaje)
4. [Tags y Atributos Semánticos](#4-tags-y-atributos-semánticos)
5. [Manejo de Errores y Excepciones](#5-manejo-de-errores-y-excepciones)
6. [Métricas Operacionales y de Negocio](#6-métricas-operacionales-y-de-negocio)
7. [Métricas SRE y Confiabilidad](#7-métricas-sre-y-confiabilidad)
8. [Casuística y Patrones de Problemas](#8-casuística-y-patrones-de-problemas)
9. [Anticipación de Eventos y Problemas](#9-anticipación-de-eventos-y-problemas)
10. [Configuraciones Avanzadas](#10-configuraciones-avanzadas)
11. [Diagramas y Visualizaciones Sugeridas](#11-diagramas-y-visualizaciones-sugeridas)

**📚 Documentos Relacionados**:
- [Guía Completa de Instrumentación](./INSTRUMENTACION.md): Configuración detallada del SDK, métricas personalizadas, logs y flujo de trazas

---

## 1. Visión General del Sistema

### 1.1 Stack Tecnológico

El laboratorio implementa un ecosistema completo de microservicios con observabilidad de nivel empresarial:

#### Microservicios
- **micro-1** (Rust): Servicio gRPC con operaciones de clima y base de datos
- **micro-2** (Go): Servicio gRPC con integración API externa y persistencia
- **micro-3** (Node.js/TypeScript): API Gateway HTTP con enrutamiento y agregación

#### Stack de Observabilidad
- **OpenTelemetry Collector**: Agregador centralizado de telemetría
- **Grafana Tempo**: Almacenamiento de trazas distribuidas
- **Prometheus**: Almacenamiento de métricas temporales
- **Grafana**: Visualización y dashboards unificados
- **PostgreSQL**: Base de datos para persistencia de datos

#### Infraestructura
- **Kubernetes**: Orquestación de contenedores
- **Linkerd**: Service mesh con mTLS automático
- **Horizontal Pod Autoscaler (HPA)**: Escalado automático basado en recursos

### 1.2 Flujo de Datos de Observabilidad

```
┌─────────────────────────────────────────────────────────────────┐
│                    APLICACIONES (3 servicios)                   │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐                      │
│  │ micro-1  │  │ micro-2  │  │ micro-3  │                      │
│  │  (Rust)  │  │   (Go)   │  │ (Node.js)│                      │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘                      │
│       │             │             │                             │
│       └─────────────┴─────────────┘                             │
│                   │ OTLP (gRPC/HTTP)                            │
└───────────────────┼─────────────────────────────────────────────┘
                    │
        ┌───────────▼───────────┐
        │  OpenTelemetry        │
        │    Collector          │
        │  - Receivers: OTLP    │
        │  - Processors: Batch, │
        │    Memory Limiter,    │
        │    Resource           │
        │  - Exporters: Tempo,  │
        │    Prometheus         │
        └───────┬───────────────┘
                │
    ┌───────────┼───────────┐
    │           │           │
┌───▼───┐  ┌───▼───┐  ┌───▼────┐
│ Tempo │  │Prometh│  │ Grafana│
│(Traces│  │  eus  │  │  (UI)  │
│ Logs) │  │(Metrics│  │        │
└───────┘  └───────┘  └────────┘
```

### 1.3 Principios de Observabilidad Implementados

1. **Instrumentación Automática**: Uso de SDKs de OpenTelemetry nativos
2. **Correlación Cross-Signal**: Traces, logs y métricas vinculados por trace_id
3. **Context Propagation**: Propagación de contexto distribuido vía gRPC metadata
4. **Semantic Conventions**: Atributos siguiendo estándares OpenTelemetry
5. **Error Tracking**: Captura estructurada de errores con contexto completo
6. **Performance Monitoring**: Métricas de latencia, throughput y recursos
7. **Business Metrics**: Métricas específicas de dominio (consultas de clima, guardado de datos)

---

## 2. Arquitectura de Observabilidad

### 2.1 Componentes del Stack

#### OpenTelemetry Collector
**Función**: Agregador centralizado que recibe, procesa y exporta telemetría

**Configuración Clave**:
- **Receivers**: OTLP (gRPC:4317, HTTP:4318), Prometheus (scraping)
- **Processors**:
  - `batch`: Agrupa datos para exportación eficiente (timeout: 10s)
  - `memory_limiter`: Previene OOM (límite: 1000MiB, check: 5s)
  - `resource`: Enriquecimiento de atributos de recurso
- **Exporters**: 
  - Tempo (traces y logs)
  - Prometheus (métricas en puerto 8889)

**Ventajas de este diseño**:
- Desacoplamiento: aplicaciones no dependen directamente de backends
- Transformación centralizada: procesamiento uniforme
- Escalabilidad: collector puede escalar independientemente

#### Grafana Tempo
**Función**: Almacenamiento de trazas distribuidas y logs

**Configuración**:
- Retención: 1 hora (configurable)
- Backend: Local storage (`/var/tempo/traces`)
- Procesadores: service-graphs, span-metrics (generación automática de métricas desde trazas)

**Beneficios**:
- Búsqueda rápida por trace_id
- Generación automática de métricas desde trazas
- Integración nativa con Grafana

#### Prometheus
**Función**: Almacenamiento de métricas time-series

**Configuración**:
- Scrape interval: 15s (global), 10s (collector)
- Retención: 200 horas
- Service discovery: Kubernetes pods con anotaciones `prometheus.io/scrape`

**Alertas Configuradas**:
- HighErrorRate: Tasa de error > 10% por 2 minutos
- HighResponseTime: P95 > 2 segundos por 3 minutos
- ServiceDown: Servicio caído por 1 minuto
- HighMemoryUsage: Uso > 80% por 5 minutos
- HighCPUUsage: CPU > 80% por 5 minutos
- LowRequestRate: Tasa < 0.01 req/s por 5 minutos

### 2.2 Integración con Service Mesh (Linkerd)

**Configuración Especial**:
- `config.linkerd.io/skip-outbound-ports: "4317,4318"`: Evita que Linkerd intercepte tráfico OTLP
- `config.linkerd.io/opaque-ports: "4317"`: Marca puertos OTLP como opacos

**Razón**: 
- El tráfico OTLP ya está estructurado y no requiere inspección de Linkerd
- Evita problemas de certificados TLS y doble encriptación
- Mejora el rendimiento al reducir overhead

### 2.3 Escalado y Confiabilidad

**Horizontal Pod Autoscaler (HPA)**:
- **micro-1/micro-2**: 1-1 réplicas (CPU: 70%, Memory: 80%)
- **api-gateway**: 2-8 réplicas (CPU: 70%, Memory: 80%)

**Pod Disruption Budgets (PDB)**:
- Garantiza disponibilidad mínima durante actualizaciones
- `minAvailable: 1` para todos los servicios

**Rolling Updates**:
- `maxSurge: 1`, `maxUnavailable: 0`: Actualizaciones sin downtime

---

## 3. Instrumentación Específica por Lenguaje

### 3.1 Rust (micro-1)

#### Características Clave
- **TracerProvider**: Configurado con OTLP gRPC exporter
- **LoggerProvider**: Separado para logs estructurados
- **Métricas**: Contadores e histogramas personalizados
- **Context Propagation**: Extracción de contexto desde gRPC metadata

#### Implementación de Traces

```rust
// Extracción de contexto desde metadata gRPC
let metadata = request.metadata();
let extractor = GrpcMetadataExtractor { metadata };
let parent_context = global::get_text_map_propagator(|propagator| 
    propagator.extract(&extractor)
);

// Creación de span con contexto padre
let tracer = global::tracer("micro-1");
let mut span = tracer.start_with_context("micro-1: get_weather", &parent_context);

// Atributos semánticos estándar
span.set_attribute(KeyValue::new("rpc.system", "grpc"));
span.set_attribute(KeyValue::new("rpc.service", "helloworld.Greeter"));
span.set_attribute(KeyValue::new("rpc.method", "GetWeather"));
span.set_attribute(KeyValue::new("service.name", "micro-1"));
span.set_attribute(KeyValue::new("service.version", "1.0.0"));
span.set_attribute(KeyValue::new("service.language", "rust"));
```

#### Métricas Personalizadas

```rust
pub struct MetricsHandler {
    pub message_counter: opentelemetry::metrics::Counter<u64>,
    pub hello_world_counter: opentelemetry::metrics::Counter<u64>,
    pub request_duration: opentelemetry::metrics::Histogram<f64>,
}

// Uso con tags
self.message_counter.add(1, &[KeyValue::new("endpoint", "send_message")]);
self.request_duration.record(duration, &[KeyValue::new("endpoint", "get_hello_world")]);
```

#### Manejo de Errores

```rust
match weather_result {
    Ok((temp, condition, humidity, wind_speed)) => {
        span.set_attribute(KeyValue::new("response.success", true));
        span.set_status(opentelemetry::trace::Status::Ok);
        // ...
    }
    Err(e) => {
        span.set_attribute(KeyValue::new("response.success", false));
        span.set_attribute(KeyValue::new("error.message", e.to_string()));
        span.set_status(opentelemetry::trace::Status::Error {
            description: e.to_string().into(),
        });
        tracing::error!(trace_id = %trace_id, span_id = %span_id, 
            "Failed to get weather for {}: {}", city, e);
    }
}
```

#### Logging Estructurado

- **Integración**: `tracing-opentelemetry` bridge + `opentelemetry-appender-tracing`
- **Formato**: JSON estructurado con `tracing_subscriber::fmt::layer().json()`
- **Correlación**: trace_id y span_id incluidos en logs automáticamente

### 3.2 Go (micro-2)

#### Características Clave
- **Múltiples TracerProviders**: Separación por servicio (main, weather, db)
- **LoggerProvider**: Logs estructurados con OpenTelemetry
- **Context Propagation**: Integración nativa con context.Context
- **Métricas**: Via OTLP directo

#### TracerProviders Separados

**Estrategia**: Usar diferentes TracerProviders para visualización diferenciada en Grafana

```go
// TracerProvider principal
MainTracerProvider = sdktrace.NewTracerProvider(
    sdktrace.WithResource(resource.NewSchemaless(
        attribute.String("service.name", "micro-2"),
        attribute.String("service.version", "1.0.0"),
        attribute.String("service.language", "go"),
    )),
)

// TracerProvider para API externa
WeatherTracerProvider = sdktrace.NewTracerProvider(
    sdktrace.WithResource(resource.NewSchemaless(
        attribute.String("service.name", "openweathermap-api"),
        attribute.String("service.version", "2.5"),
    )),
)

// TracerProvider para base de datos
DBTracerProvider = sdktrace.NewTracerProvider(
    sdktrace.WithResource(resource.NewSchemaless(
        attribute.String("service.name", "postgres"),
        attribute.String("db.system", "postgresql"),
    )),
)
```

#### Atributos Detallados en Spans

```go
ctx, span := tracer.Start(ctx, "micro-2: Ping",
    trace.WithAttributes(
        attribute.String("rpc.system", "grpc"),
        attribute.String("rpc.service", "micro.MicroService"),
        attribute.String("rpc.method", "Ping"),
        attribute.String("service.name", "micro-2"),
        attribute.String("service.version", "1.0.0"),
        attribute.String("service.language", "go"),
        attribute.String("service.framework", "grpc"),
        attribute.String("runtime.name", runtime.Compiler),
        attribute.String("runtime.version", runtime.Version()),
        attribute.String("runtime.os", runtime.GOOS),
        attribute.String("runtime.arch", runtime.GOARCH),
        attribute.Int("runtime.num_goroutines", runtime.NumGoroutine()),
    ),
)
```

#### Logging Contextual

```go
func logWithContext(ctx context.Context, level string, message string, fields map[string]interface{}) {
    logger := config.MainLoggerProvider.Logger("micro-2")
    span := trace.SpanFromContext(ctx)
    spanContext := span.SpanContext()
    
    // Correlación automática con traces
    if spanContext.IsValid() {
        attrs = append(attrs,
            otellog.String("trace.id", spanContext.TraceID().String()),
            otellog.String("span.id", spanContext.SpanID().String()),
            otellog.String("trace.flags", spanContext.TraceFlags().String()),
        )
    }
    
    // Campos adicionales del contexto de negocio
    if fields != nil {
        for k, v := range fields {
            // Conversión tipo-segura de valores
            attrs = append(attrs, otellog.String(k, fmt.Sprintf("%v", v)))
        }
    }
}
```

#### Error Recording

```go
if err != nil {
    span.SetAttributes(attribute.Bool("response.success", false))
    span.SetStatus(codes.Error, err.Error())
    span.RecordError(err)  // Registra stack trace completo
    
    logWithContext(ctx, "error", "Failed to get weather", map[string]interface{}{
        "trace_id": traceID,
        "span_id":  spanID,
        "error":    err.Error(),
    })
    return nil, fmt.Errorf("failed to get weather: %v", err)
}
```

### 3.3 Node.js/TypeScript (micro-3 / API Gateway)

#### Características Clave
- **HTTP Server**: Instrumentación de requests HTTP
- **Timeouts**: Manejo de timeouts con métricas
- **Error Handling**: Captura estructurada de errores
- **Métricas**: Contadores y histogramas por endpoint

#### Instrumentación de Requests

```typescript
const span = tracer.startSpan(`Handling ${req.method} ${req.url}`, {
  attributes: {
    'http.method': req.method || 'UNKNOWN',
    'http.url': req.url || '/unknown',
    'request.id': requestId,
  }
});

// Timeout protection
const timeout = setTimeout(() => {
  if (!res.headersSent) {
    res.writeHead(504, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ 
      error: 'Gateway timeout',
      requestId,
      timestamp: new Date().toISOString()
    }));
    span.setStatus({ code: SpanStatusCode.ERROR, message: 'Gateway timeout' });
    span.end();
  }
}, 30000);
```

#### Logging Estructurado

```typescript
const logger = logs.getLoggerProvider().getLogger('api-gateway', '1.0.0');

const activeSpan = trace.getActiveSpan();
if (activeSpan) {
  const spanContext = activeSpan.spanContext();
  logger.emit({
    severityNumber: SeverityNumber.INFO,
    severityText: 'INFO',
    body: `Processing request #${requestId}: ${req.method} ${req.url}`,
    attributes: {
      'request.id': requestId,
      'trace.id': spanContext.traceId,
      'span.id': spanContext.spanId,
    },
  });
}
```

#### Manejo Seguro de Operaciones

```typescript
private async safeExecute<T>(
  operation: () => Promise<T>,
  operationName: string,
  fallbackValue: T
): Promise<T> {
  try {
    return await operation();
  } catch (error) {
    this.errorCounter++;
    logToOTel('error', `Error in ${operationName}:`, { 
      error: error instanceof Error ? error.message : String(error),
      errorCounter: this.errorCounter 
    });
    return fallbackValue;
  }
}
```

#### Métricas de Negocio

```typescript
export class MetricsHandler {
  private requestCounter;
  private requestDuration;

  recordRequest(endpoint: string, method: string): void {
    this.requestCounter.add(1, { endpoint, method });
  }

  recordRequestDuration(duration: number, endpoint: string, method: string): void {
    this.requestDuration.record(duration, { endpoint, method });
  }
}
```

---

## 4. Tags y Atributos Semánticos

### 4.1 Convenciones Semánticas de OpenTelemetry

El proyecto implementa extensivamente las convenciones semánticas de OpenTelemetry para garantizar:
- **Consistencia**: Mismo formato de atributos en todos los servicios
- **Interoperabilidad**: Compatibilidad con herramientas estándar
- **Búsqueda**: Facilita queries y filtros en Grafana/Prometheus

### 4.2 Categorías de Atributos

#### Atributos de Recurso (Resource Attributes)
- `service.name`: Identificador del servicio ("micro-1", "micro-2", "api-gateway")
- `service.version`: Versión del servicio ("1.0.0")
- `service.language`: Lenguaje de programación ("rust", "go", "nodejs")
- `service.framework`: Framework utilizado ("grpc", "http")
- `application`: Aplicación padre ("lab-observability")

#### Atributos RPC (gRPC)
- `rpc.system`: "grpc"
- `rpc.service`: Nombre del servicio gRPC ("helloworld.Greeter", "micro.MicroService")
- `rpc.method`: Método gRPC ("GetWeather", "Ping", "SaveWeatherData")
- `rpc.grpc.status_code`: Código de estado gRPC ("0" = OK)

#### Atributos HTTP
- `http.method`: Método HTTP ("GET", "POST")
- `http.url`: URL completa
- `http.route`: Ruta sin parámetros ("/weather")
- `http.status_code`: Código de respuesta (200, 404, 500, etc.)
- `http.flavor`: Versión HTTP ("1.1")
- `http.response.size`: Tamaño de respuesta en bytes

#### Atributos de Base de Datos
- `db.system`: Sistema de BD ("postgresql")
- `db.name`: Nombre de la base de datos ("observability")
- `db.user`: Usuario de conexión
- `db.operation`: Operación ("SELECT", "INSERT")
- `db.statement`: Query SQL (con parámetros)
- `db.result.count`: Número de registros afectados/retornados
- `db.record.id`: ID del registro insertado

#### Atributos de Clima (Dominio Específico)
- `weather.city`: Ciudad consultada
- `weather.temperature`: Temperatura en grados Celsius
- `weather.condition`: Condición meteorológica
- `weather.humidity`: Humedad relativa
- `weather.wind_speed`: Velocidad del viento

#### Atributos de Runtime
- `runtime.name`: Compilador/interprete ("rustc", runtime.Compiler, "node")
- `runtime.version`: Versión del runtime
- `runtime.os`: Sistema operativo ("linux", "darwin")
- `runtime.arch`: Arquitectura ("amd64", "arm64")
- `runtime.num_goroutines`: Número de goroutines (Go específico)

#### Atributos de Request/Response
- `request.id`: Identificador único de request
- `request.timestamp`: Timestamp de inicio
- `request.counter`: Contador de requests
- `response.success`: Boolean indicando éxito
- `response.message`: Mensaje de respuesta
- `response.duration_ms`: Duración en milisegundos
- `response.duration_seconds`: Duración en segundos
- `response.message_length`: Longitud del mensaje

#### Atributos de Error
- `error`: Boolean indicando presencia de error
- `error.message`: Mensaje de error descriptivo
- `error.type`: Tipo de error (si aplicable)

### 4.3 Tags para Métricas

Las métricas utilizan tags (labels) para dimensionar:

**Métricas de Request**:
- `endpoint`: Ruta del endpoint ("/weather/micro2", "send_message")
- `method`: Método HTTP ("GET", "POST")
- `status`: Código de estado ("200", "500", "404")

**Métricas de Negocio**:
- `city`: Ciudad para operaciones de clima
- `operation`: Tipo de operación ("get_weather", "save_data")

### 4.4 Beneficios de esta Estrategia

1. **Búsqueda Eficiente**: Filtros por atributos estándar en Grafana
2. **Correlación Automática**: Linking entre traces, logs y métricas
3. **Dashboards Reutilizables**: Plantillas basadas en convenciones
4. **Onboarding Rápido**: Desarrolladores conocen el formato estándar
5. **Integración con Herramientas**: Compatibilidad con ecosistema OpenTelemetry

---

## 5. Manejo de Errores y Excepciones

### 5.1 Estrategia Integral de Error Handling

El laboratorio implementa un manejo de errores estructurado en múltiples capas:

#### Nivel 1: Captura en Spans (OpenTelemetry)

**Todos los errores se registran en spans con**:
- Estado del span: `Status::Error` o `codes.Error`
- Atributos de error: `error.message`, `error.type`
- Stack trace: `span.RecordError(err)` (Go) o equivalente
- Contexto: trace_id, span_id para correlación

**Ejemplo Rust**:
```rust
Err(e) => {
    span.set_attribute(KeyValue::new("response.success", false));
    span.set_attribute(KeyValue::new("error.message", e.to_string()));
    span.set_status(opentelemetry::trace::Status::Error {
        description: e.to_string().into(),
    });
    span.end();
    Err(tonic::Status::internal(format!("Failed to get weather: {}", e)))
}
```

**Ejemplo Go**:
```go
if err != nil {
    span.SetAttributes(attribute.Bool("response.success", false))
    span.SetStatus(codes.Error, err.Error())
    span.RecordError(err)  // Captura stack trace completo
    return nil, fmt.Errorf("failed to get weather: %v", err)
}
```

#### Nivel 2: Logging Estructurado

**Los errores se loguean con**:
- Severidad apropiada: ERROR, WARN
- Trace ID y Span ID para correlación
- Contexto adicional: request_id, operación, parámetros
- Mensaje descriptivo con detalles técnicos

**Ejemplo**:
```go
logWithContext(ctx, "error", fmt.Sprintf("Failed to get weather for %s", req.City), map[string]interface{}{
    "trace_id": traceID,
    "span_id":  spanID,
    "error":    err.Error(),
})
```

#### Nivel 3: Métricas de Error

**Contadores de errores por**:
- Endpoint/método
- Tipo de error
- Código de estado HTTP/gRPC

**Implementación**:
```typescript
catch (error) {
  errorCount++;
  // Métricas se registran automáticamente vía status code en span
  span.setStatus({ code: SpanStatusCode.ERROR });
}
```

### 5.2 Tipos de Errores Capturados

#### Errores de Validación
- **Lugar**: micro-1 (Rust) - validación de longitud de mensaje
- **Manejo**: Status gRPC `InvalidArgument`
- **Instrumentación**: Span con atributo `error.type: "validation"`

```rust
if message.is_empty() || message.len() > 1000 {
    tracing::warn!("Invalid message received: length={}", message.len());
    return Err(tonic::Status::invalid_argument("Invalid message length"));
}
```

#### Errores de API Externa
- **Lugar**: micro-1/micro-2 - llamadas a OpenWeatherMap API
- **Manejo**: Retry lógico, fallback a error estructurado
- **Instrumentación**: Span hijo con atributos HTTP del error

```rust
match response.status() {
    status if status.is_success() => { /* ... */ }
    _ => {
        span.set_attribute(KeyValue::new("error", true));
        span.set_attribute(KeyValue::new("error.message", format!("HTTP error: {}", status)));
        span.set_status(opentelemetry::trace::Status::Error {
            description: format!("HTTP error: {}", status).into(),
        });
        Err(format!("HTTP error: {}", status).into())
    }
}
```

#### Errores de Base de Datos
- **Lugar**: micro-1/micro-2 - operaciones PostgreSQL
- **Manejo**: Propagación con contexto completo
- **Instrumentación**: Span de BD con atributos de query y error

```go
if err != nil {
    span.SetStatus(codes.Error, err.Error())
    span.RecordError(err)
    return nil, err
}
```

#### Errores de Timeout
- **Lugar**: API Gateway (micro-3) - timeouts de 30s
- **Manejo**: Respuesta 504 Gateway Timeout
- **Instrumentación**: Span con atributo `error.type: "timeout"`

```typescript
const timeout = setTimeout(() => {
  if (!res.headersSent) {
    res.writeHead(504, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ 
      error: 'Gateway timeout',
      requestId,
      timestamp: new Date().toISOString()
    }));
    span.setStatus({ code: SpanStatusCode.ERROR, message: 'Gateway timeout' });
  }
}, 30000);
```

#### Errores de Panic (Rust)
- **Lugar**: micro-1 - protección contra panics
- **Manejo**: Catch con `catch_unwind` y logging estructurado
- **Instrumentación**: Span con error y log de panic

```rust
match std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
    self.service.send_message(request.get_ref())
})) {
    Ok(response) => Ok(tonic::Response::new(response)),
    Err(_) => {
        tracing::error!("Panic occurred while processing message");
        Err(tonic::Status::internal("Internal server error"))
    }
}
```

### 5.3 Correlación de Errores

**Estrategia de correlación**:
1. **Trace ID**: Único por request, propagado a través de servicios
2. **Span ID**: Único por operación dentro de un trace
3. **Request ID**: Identificador de request en API Gateway
4. **Error ID**: Hash del error para agrupación (futuro)

**Flujo de correlación**:
```
Request → API Gateway (request_id: 123, trace_id: abc)
  ↓
gRPC call → micro-2 (trace_id: abc propagado, span_id: def)
  ↓
DB query → (trace_id: abc, span_id: def, child_span_id: ghi)
  ↓
Error ocurre → Span marca error, log con trace_id: abc
  ↓
Grafana: Buscar trace_id: abc → Ver toda la cadena de errores
```

### 5.4 Alertas Basadas en Errores

**Prometheus Rules configuradas**:

```yaml
- alert: HighErrorRate
  expr: rate(http_requests_total{status=~"5.."}[5m]) / rate(http_requests_total[5m]) > 0.1
  for: 2m
  labels:
    severity: critical
  annotations:
    summary: "High error rate detected"
    description: "Error rate is {{ $value }} for service {{ $labels.service }}"
```

**Métricas de error disponibles**:
- `rate(http_requests_total{status=~"5.."}[5m])`: Tasa de errores 5xx
- `rate(http_requests_total{status=~"4.."}[5m])`: Tasa de errores 4xx
- `rate(grpc_requests_total{status_code!="0"}[5m])`: Tasa de errores gRPC

---

## 6. Métricas Operacionales y de Negocio

### 6.1 Métricas Operacionales

#### Request Rate (Throughput)
- **Métrica**: `http_requests_total` (counter)
- **Tags**: `endpoint`, `method`, `status`
- **Uso**: Monitoreo de carga, detección de picos
- **Alerta**: `LowRequestRate` si < 0.01 req/s por 5 minutos

#### Latency (Response Time)
- **Métrica**: `http_request_duration_seconds` (histogram)
- **Tags**: `endpoint`, `method`
- **Percentiles**: p50, p95, p99
- **Alerta**: `HighResponseTime` si p95 > 2s por 3 minutos

#### Error Rate
- **Métrica**: `rate(http_requests_total{status=~"5.."}[5m])`
- **Cálculo**: Errores 5xx / Total requests
- **Alerta**: `HighErrorRate` si > 10% por 2 minutos

#### Resource Usage
- **CPU**: `container_cpu_usage_seconds_total`
- **Memory**: `container_memory_usage_bytes`
- **Alerta**: `HighCPUUsage` si > 80% por 5 minutos
- **Alerta**: `HighMemoryUsage` si > 80% por 5 minutos

### 6.2 Métricas de Negocio

#### Operaciones de Clima
- **Métrica**: `messages_processed_total` (micro-1)
- **Tags**: `endpoint` ("send_message")
- **Uso**: Contador de mensajes procesados

- **Métrica**: `hello_world_requests_total` (micro-1)
- **Tags**: `endpoint` ("get_hello_world")
- **Uso**: Contador de requests hello world

#### Consultas de Clima por Ciudad
- **Métrica**: Implícita en traces con atributo `weather.city`
- **Uso**: Análisis de ciudades más consultadas
- **Query Grafana**: `{weather.city="Madrid"}`

#### Guardado de Datos
- **Métrica**: Contador implícito en spans de `SaveWeatherData`
- **Atributo**: `db.result.count` = 1
- **Uso**: Tasa de guardado de datos meteorológicos

#### Historial Consultado
- **Métrica**: `db.result.count` en spans de `GetWeatherHistory`
- **Uso**: Número de registros retornados por consulta
- **Análisis**: Promedio de registros por consulta

### 6.3 Métricas Derivadas (Service Level Indicators)

#### Availability (Disponibilidad)
- **Cálculo**: `(total_requests - errors_5xx) / total_requests * 100`
- **Objetivo**: > 99.9% (SLA típico)
- **Métrica Prometheus**: 
  ```promql
  100 * (1 - (rate(http_requests_total{status=~"5.."}[5m]) / rate(http_requests_total[5m])))
  ```

#### Success Rate (Tasa de Éxito)
- **Cálculo**: Similar a availability pero incluye 4xx
- **Métrica Prometheus**:
  ```promql
  rate(http_requests_total{status=~"2.."}[5m]) / rate(http_requests_total[5m])
  ```

#### Request Rate por Servicio
- **Cálculo**: `rate(http_requests_total[5m])`
- **Dimensionado por**: `service.name`
- **Uso**: Comparación de carga entre servicios

### 6.4 Métricas de Performance

#### Throughput por Endpoint
- **Métrica**: `rate(http_requests_total{endpoint="/weather/micro2"}[5m])`
- **Uso**: Identificar endpoints más utilizados
- **Visualización**: Gráfico de barras por endpoint

#### Latency Distribution
- **Métrica**: Histograma `http_request_duration_seconds`
- **Buckets**: Automáticos por OpenTelemetry
- **Visualización**: Heatmap de latencia

#### Database Query Performance
- **Métrica**: `db.result.count`, `response.duration_ms` en spans
- **Uso**: Identificar queries lentas
- **Análisis**: Percentiles de duración de queries

---

## 7. Métricas SRE y Confiabilidad

### 7.1 Service Level Objectives (SLOs)

#### Latency SLO
- **Objetivo**: 95% de requests < 2 segundos
- **Métrica**: `histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))`
- **Alerta**: Si p95 > 2s por 3 minutos

#### Error Rate SLO
- **Objetivo**: < 1% de error rate
- **Métrica**: `rate(http_requests_total{status=~"5.."}[5m]) / rate(http_requests_total[5m])`
- **Alerta**: Si error rate > 10% por 2 minutos

#### Availability SLO
- **Objetivo**: 99.9% uptime
- **Métrica**: `up{job=~"micro.*|api-gateway"}`
- **Alerta**: Si `up == 0` por 1 minuto

### 7.2 Error Budgets

**Cálculo de Error Budget**:
- **Error Budget = 100% - SLO**
- **Ejemplo**: Si SLO = 99.9%, Error Budget = 0.1%
- **Consumo**: Errores reales consumen el error budget

**Métrica Prometheus**:
```promql
# Error budget restante
1 - (rate(http_requests_total{status=~"5.."}[5m]) / rate(http_requests_total[5m]))
```

### 7.3 Métricas de Confiabilidad

#### Mean Time Between Failures (MTBF)
- **Cálculo**: Tiempo promedio entre fallos
- **Métrica**: Derivada de logs de errores y alertas
- **Uso**: Medición de estabilidad del sistema

#### Mean Time To Recovery (MTTR)
- **Cálculo**: Tiempo promedio de recuperación
- **Métrica**: Timestamp de error → Timestamp de recuperación
- **Uso**: Eficiencia de procesos de remediación

#### Service Health Score
- **Cálculo**: Combinación de múltiples métricas
- **Componentes**: 
  - Availability (peso: 40%)
  - Latency (peso: 30%)
  - Error Rate (peso: 30%)
- **Fórmula**: `(availability * 0.4) + ((1 - latency_penalty) * 0.3) + ((1 - error_rate) * 0.3)`

### 7.4 Capacity Planning

#### Resource Utilization Trends
- **Métrica**: `container_cpu_usage_seconds_total`, `container_memory_usage_bytes`
- **Uso**: Proyección de crecimiento de recursos
- **Visualización**: Gráfico de tendencia con línea de regresión

#### Request Rate Trends
- **Métrica**: `rate(http_requests_total[1h])`
- **Uso**: Predecir crecimiento de carga
- **Análisis**: Detección de patrones estacionales

#### Scaling Metrics
- **HPA**: Métricas de escalado automático
- **Trigger**: CPU > 70% o Memory > 80%
- **Monitoreo**: Número de réplicas actuales vs. capacidad

### 7.5 Alertas SRE

**Configuradas en Prometheus Rules**:

1. **ServiceDown**: Critical - Servicio caído
2. **HighErrorRate**: Critical - Tasa de error > 10%
3. **HighResponseTime**: Warning - Latencia p95 > 2s
4. **HighMemoryUsage**: Warning - Memoria > 80%
5. **HighCPUUsage**: Warning - CPU > 80%
6. **LowRequestRate**: Warning - Tasa < 0.01 req/s

**Runbook Sugerido**:
- **ServiceDown**: Verificar pods, logs, restart si necesario
- **HighErrorRate**: Revisar logs recientes, traces con errores
- **HighResponseTime**: Analizar bottlenecks, revisar queries DB
- **HighMemoryUsage**: Escalar horizontalmente, optimizar código
- **HighCPUUsage**: Escalar horizontalmente, optimizar algoritmos
- **LowRequestRate**: Verificar load balancer, DNS, red

---

## 8. Casuística y Patrones de Problemas

### 8.1 Casos de Uso Documentados

#### Caso 1: Error en API Externa
**Escenario**: OpenWeatherMap API no responde o retorna error

**Síntomas Observables**:
- Traces: Span `http.get.weather` con `status_code: 0` o `status_code: 5xx`
- Logs: Error con mensaje "HTTP error: 503" o "timeout"
- Métricas: Aumento en `error_rate` para endpoint `/weather/micro2`

**Diagnóstico**:
1. Buscar en Grafana: `{service.name="openweathermap-api"} {error=true}`
2. Revisar trace completo: Ver span padre (micro-1/micro-2) y span hijo (API externa)
3. Verificar logs: Correlacionar con trace_id
4. Analizar métricas: Tasa de error en últimos 5 minutos

**Remediación**:
- Implementar retry con backoff exponencial
- Cache de respuestas anteriores
- Fallback a datos históricos de BD

#### Caso 2: Query Lenta en Base de Datos
**Escenario**: Query `GetWeatherHistory` toma > 5 segundos

**Síntomas Observables**:
- Traces: Span `postgres.query.execute` con `duration_ms > 5000`
- Logs: Warning sobre query lenta
- Métricas: Histograma de latencia con cola larga en percentiles altos

**Diagnóstico**:
1. Buscar en Tempo: `{db.operation="SELECT"} {duration_ms > 5000}`
2. Analizar query: Ver atributo `db.statement` en span
3. Revisar índices: Verificar si falta índice en columna `city` o `timestamp`
4. Métricas: `histogram_quantile(0.95, rate(db_query_duration_ms_bucket[5m]))`

**Remediación**:
- Agregar índice: `CREATE INDEX idx_weather_city_timestamp ON weather_data(city, timestamp DESC);`
- Optimizar query: Usar LIMIT más pequeño, agregar WHERE más específico
- Considerar cache: Redis para queries frecuentes

#### Caso 3: Timeout en API Gateway
**Escenario**: Request toma > 30 segundos, Gateway retorna 504

**Síntomas Observables**:
- Traces: Span con `error.message="Gateway timeout"`
- Logs: Error con `request.id` y `trace_id`
- Métricas: Contador de errores 504 incrementado

**Diagnóstico**:
1. Buscar trace completo: Ver qué servicio está causando el delay
2. Analizar spans: Identificar span más largo en el trace
3. Revisar métricas: `rate(http_requests_total{status="504"}[5m])`
4. Verificar dependencias: Estado de micro-1, micro-2, BD

**Remediación**:
- Aumentar timeout si es legítimo (p. ej., query compleja)
- Optimizar servicio lento identificado
- Implementar circuit breaker para servicios externos
- Agregar retry con timeout más corto

#### Caso 4: Memory Leak
**Escenario**: Memoria del pod crece continuamente hasta OOM

**Síntomas Observables**:
- Métricas: `container_memory_usage_bytes` creciendo monótonamente
- Alerta: `HighMemoryUsage` activada
- Logs: Pod reiniciado por OOMKilled

**Diagnóstico**:
1. Monitorear métricas: `container_memory_usage_bytes{pod="micro-1-xxx"}`
2. Analizar tendencia: Gráfico de memoria en últimos 24 horas
3. Revisar código: Buscar acumulación de objetos, goroutines no cerradas
4. Profiling: Usar herramientas de profiling (pprof para Go, perf para Rust)

**Remediación**:
- Corregir memory leak en código
- Aumentar límite de memoria temporalmente
- Escalar horizontalmente para distribuir carga
- Implementar garbage collection tuning

#### Caso 5: Cascading Failure
**Escenario**: Un servicio falla, causando fallos en cascada

**Síntomas Observables**:
- Traces: Múltiples errores en cadena de servicios
- Métricas: Error rate aumentando en múltiples servicios
- Logs: Errores propagándose de servicio a servicio

**Diagnóstico**:
1. Identificar servicio origen: Buscar primer error en timeline
2. Analizar dependencias: Ver qué servicios dependen del fallido
3. Revisar traces: Seguir trace_id a través de servicios
4. Métricas: `rate(http_requests_total{status=~"5.."}[1m])` por servicio

**Remediación**:
- Implementar circuit breaker
- Agregar retry con exponential backoff
- Timeouts más cortos para evitar cascading
- Fallback a respuestas cached o default

### 8.2 Patrones de Problemas Comunes

#### Patrón 1: Thundering Herd
**Descripción**: Múltiples requests simultáneos a mismo recurso

**Indicadores**:
- Pico súbito en request rate
- Múltiples spans con mismo endpoint en mismo momento
- Aumento de latencia correlacionado con pico

**Solución**:
- Rate limiting
- Cache con TTL
- Queue para procesamiento asíncrono

#### Patrón 2: Hot Spot
**Descripción**: Un endpoint específico recibe mayoría del tráfico

**Indicadores**:
- `rate(http_requests_total{endpoint="X"}[5m])` >> otros endpoints
- Latencia alta solo para ese endpoint
- Recursos saturados

**Solución**:
- Escalar específicamente ese servicio
- Optimizar código del endpoint
- Implementar cache agresivo
- Distribuir carga con load balancer

#### Patrón 3: Slow Query
**Descripción**: Query de BD que gradualmente se vuelve más lenta

**Indicadores**:
- `histogram_quantile(0.95, rate(db_query_duration_ms_bucket[5m]))` creciendo
- Spans de BD con `duration_ms` aumentando
- Correlación con crecimiento de datos

**Solución**:
- Agregar índices
- Optimizar query
- Particionar tabla
- Implementar paginación

#### Patrón 4: Resource Exhaustion
**Descripción**: Servicio consume todos los recursos disponibles

**Indicadores**:
- `container_cpu_usage_seconds_total` o `container_memory_usage_bytes` cerca de límite
- Alertas de alta utilización
- Degradación de performance

**Solución**:
- Escalar horizontalmente (HPA)
- Optimizar código
- Aumentar límites de recursos
- Implementar rate limiting

---

## 9. Anticipación de Eventos y Problemas

### 9.1 Técnicas de Anticipación Implementadas

#### Alertas Proactivas
**Estrategia**: Alertar antes de que ocurra un problema crítico

**Ejemplos**:
- `HighMemoryUsage`: Alerta al 80%, no al 100% (permite acción preventiva)
- `HighResponseTime`: Alerta cuando p95 > 2s, no cuando servicio está caído
- `LowRequestRate`: Detecta problemas de conectividad antes de fallos completos

#### Anomaly Detection (Futuro)
**Oportunidad**: Implementar detección de anomalías con Prometheus

**Métricas candidatas**:
- Request rate: Detectar picos inesperados
- Error rate: Detectar aumento gradual de errores
- Latency: Detectar degradación gradual de performance

**Herramientas sugeridas**:
- Prometheus `predict_linear()`: Predicción basada en tendencia
- Grafana ML Plugin: Machine learning para detección de anomalías
- Prometheus Alertmanager: Agregación de alertas similares

### 9.2 Capacity Planning

#### Métricas de Crecimiento
**Tendencias a monitorear**:
- Request rate: `rate(http_requests_total[24h])` con `predict_linear()`
- Resource usage: Proyección de CPU/memoria basada en crecimiento
- Storage: Crecimiento de datos en BD

**Query Prometheus ejemplo**:
```promql
# Predicción de request rate en 7 días
predict_linear(rate(http_requests_total[24h])[1h:], 7*24*3600)
```

#### Escalado Proactivo
**HPA configuración actual**:
- Escala cuando CPU > 70% o Memory > 80%
- Min replicas: 1-2
- Max replicas: 8

**Mejoras sugeridas**:
- Escalar basado en request rate, no solo recursos
- Pre-escalar basado en patrones históricos (p. ej., hora pico)
- Escalar basado en métricas de negocio (p. ej., número de consultas de clima)

### 9.3 Health Checks y Readiness Probes

#### Kubernetes Probes
**Implementadas**:
- `readinessProbe`: Verifica que servicio está listo
- `livenessProbe`: Verifica que servicio está vivo

**Ejemplo**:
```yaml
readinessProbe:
  httpGet:
    path: /-/ready
    port: 9090
  initialDelaySeconds: 30
  periodSeconds: 10
```

**Beneficios**:
- Evita enrutar tráfico a pods no listos
- Reinicia pods que no responden
- Mejora disponibilidad durante deployments

### 9.4 Circuit Breaker Pattern (Futuro)

**Oportunidad**: Implementar circuit breaker para servicios externos

**Beneficios**:
- Evita cascading failures
- Reduce carga en servicios fallidos
- Permite recuperación automática

**Implementación sugerida**:
- Go: `gobreaker` library
- Rust: `tower` middleware con circuit breaker
- Node.js: `opossum` library

**Métricas a agregar**:
- Circuit breaker state (open/closed/half-open)
- Number of failures before opening
- Time until retry

### 9.5 Distributed Tracing para Root Cause Analysis

#### Análisis de Traces Complejos
**Capacidad actual**:
- Traces end-to-end desde API Gateway hasta BD
- Spans anidados mostrando jerarquía de llamadas
- Atributos detallados en cada span

**Uso para anticipación**:
1. **Identificar patrones de latencia**: Analizar traces lentos para identificar bottlenecks comunes
2. **Detectar dependencias críticas**: Servicios que aparecen en mayoría de traces
3. **Monitorear degradación gradual**: Comparar latencia de spans a lo largo del tiempo

**Query Grafana ejemplo**:
```
# Traces con latencia > 5s en últimos 5 minutos
{duration > 5000ms} AND {service.name="micro-2"}
```

### 9.6 Log Aggregation y Análisis

#### Búsqueda de Patrones en Logs
**Capacidad actual**:
- Logs estructurados con trace_id
- Severidad niveles (INFO, WARN, ERROR)
- Atributos contextuales

**Uso para anticipación**:
1. **Detección de errores recurrentes**: Buscar mismo error message múltiples veces
2. **Análisis de frecuencia**: Contar ocurrencias de warnings/errors
3. **Correlación temporal**: Errores que ocurren en momentos específicos

**Query Loki ejemplo** (futuro):
```
{service.name="micro-2"} |= "error" | json | rate(5m)
```

---

## 10. Configuraciones Avanzadas

### 10.1 OpenTelemetry Collector

#### Processors Avanzados

**Batch Processor**:
```yaml
batch:
  timeout: 10s        # Tiempo máximo de espera antes de exportar
  send_batch_size: 512  # Tamaño máximo de batch
  send_batch_max_size: 0  # Sin límite máximo
```

**Memory Limiter**:
```yaml
memory_limiter:
  check_interval: 5s    # Frecuencia de verificación
  limit_mib: 1000       # Límite de memoria en MiB
  spike_limit_mib: 500  # Límite para spikes temporales
```

**Resource Processor**:
```yaml
resource:
  attributes:
    - key: service.name
      from_attribute: service.name
      action: upsert     # Actualizar o crear
    - key: environment
      value: production
      action: upsert
```

#### Exporters Configurados

**Tempo Exporter**:
- Endpoint: `tempo:4317` (gRPC)
- TLS: Insecure (entorno de desarrollo)
- Batch export: Agrupado por collector

**Prometheus Exporter**:
- Endpoint: `0.0.0.0:8889`
- Namespace: `otel`
- Enable OpenMetrics: true

### 10.2 Grafana Tempo

#### Configuración de Retención
```yaml
compactor:
  compaction:
    block_retention: 1h              # Retención de bloques
    compacted_block_retention: 10m   # Retención de bloques compactados
```

#### Generación de Métricas desde Traces
```yaml
overrides:
  defaults:
    metrics_generator:
      processors: [service-graphs, span-metrics]
```

**Beneficios**:
- Métricas automáticas de latencia por servicio
- Service graphs (mapa de dependencias)
- Reducción de overhead de instrumentación

### 10.3 Prometheus

#### Service Discovery
```yaml
scrape_configs:
  - job_name: 'microservices'
    kubernetes_sd_configs:
      - role: pod
    relabel_configs:
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
        action: keep
        regex: true
```

**Anotaciones requeridas en pods**:
```yaml
annotations:
  prometheus.io/scrape: "true"
  prometheus.io/port: "8080"
  prometheus.io/path: "/metrics"
```

#### Retención de Datos
```yaml
- --storage.tsdb.retention.time=200h
```

**Consideraciones**:
- 200 horas = ~8 días
- Ajustar según necesidades de análisis histórico
- Considerar almacenamiento externo para retención larga

### 10.4 Kubernetes Configurations

#### Resource Limits y Requests
```yaml
resources:
  limits:
    memory: "1Gi"
    cpu: "1000m"
  requests:
    memory: "512Mi"
    cpu: "500m"
```

**Estrategia**:
- Requests: Garantía mínima de recursos
- Limits: Máximo permitido (evita OOM)
- Ratio recomendado: Limits = 2x Requests

#### Horizontal Pod Autoscaler
```yaml
metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
```

**Comportamiento**:
- Escala cuando CPU > 70% o Memory > 80%
- Cool-down period: Evita escalado frecuente
- Min/Max replicas: Límites de escalado

#### Pod Disruption Budget
```yaml
spec:
  minAvailable: 1
```

**Beneficio**:
- Garantiza disponibilidad durante actualizaciones
- Evita downtime durante maintenance
- Compatible con rolling updates

### 10.5 Linkerd Integration

#### Anotaciones de Puertos
```yaml
annotations:
  config.linkerd.io/skip-outbound-ports: "4317,4318"
  config.linkerd.io/opaque-ports: "4317"
```

**Razón técnica**:
- OTLP usa protocolos binarios (gRPC) y estructurados (HTTP)
- No requiere inspección de Linkerd
- Evita overhead de mTLS para telemetría interna

#### Service Mesh Benefits
- mTLS automático entre servicios
- Métricas de red (latencia, throughput, errores)
- Health checks automáticos
- Traffic splitting para canary deployments

---

## 11. Diagramas y Visualizaciones Sugeridas

### 11.1 Diagramas de Arquitectura

#### Diagrama 1: Arquitectura de Observabilidad Completa
**Tipo**: Diagrama de flujo de datos
**Componentes**:
- 3 microservicios (micro-1, micro-2, micro-3)
- OpenTelemetry Collector
- Tempo, Prometheus, Grafana
- PostgreSQL
- Flujos OTLP (gRPC/HTTP)

**Elementos visuales**:
- Flechas indicando dirección de datos
- Colores por tipo de señal (traces: azul, metrics: verde, logs: amarillo)
- Grupos lógicos (aplicaciones, observabilidad, almacenamiento)

#### Diagrama 2: Flujo de Request End-to-End
**Tipo**: Sequence diagram
**Actores**:
- Cliente
- API Gateway (micro-3)
- micro-2 (Go)
- OpenWeatherMap API
- PostgreSQL
- OpenTelemetry Collector
- Tempo

**Mensajes**:
- HTTP request
- gRPC calls
- Trace propagation (trace_id)
- Span creation
- Error propagation

### 11.2 Infografías Sugeridas

#### Infografía 1: Tres Pilares de Observabilidad
**Título**: "Logs, Traces y Métricas: Los Tres Pilares"
**Contenido**:
- **Logs**: Qué pasó, cuándo, contexto
- **Traces**: Dónde pasó, flujo completo
- **Métricas**: Cuánto, frecuencia, tendencias
- **Correlación**: Cómo se conectan (trace_id)

#### Infografía 2: Stack de Observabilidad
**Título**: "De Aplicación a Dashboard: El Viaje de los Datos"
**Pasos**:
1. Instrumentación en código (SDK OpenTelemetry)
2. Exportación vía OTLP (gRPC/HTTP)
3. Procesamiento en Collector (batch, enrich)
4. Almacenamiento (Tempo, Prometheus)
5. Visualización (Grafana)

#### Infografía 3: Métricas SRE
**Título**: "Medición de Confiabilidad: SLOs, SLIs y Error Budgets"
**Contenido**:
- **SLI**: Service Level Indicator (disponibilidad, latencia)
- **SLO**: Service Level Objective (objetivo: 99.9%)
- **SLA**: Service Level Agreement (contrato con cliente)
- **Error Budget**: Presupuesto de errores permitidos

### 11.3 Dashboards Recomendados

#### Dashboard 1: Overview de Sistema
**Paneles**:
- Request rate por servicio (gráfico de líneas)
- Error rate por servicio (gráfico de líneas)
- Latencia p50, p95, p99 (gráfico de líneas)
- Uso de CPU/Memoria (gráfico de áreas)
- Estado de servicios (estado: verde/amarillo/rojo)

#### Dashboard 2: Análisis de Traces
**Paneles**:
- Traces por servicio (gráfico de barras)
- Latencia de spans (heatmap)
- Error rate por operación (gráfico de barras)
- Service graph (gráfico de dependencias)
- Traces más lentos (tabla)

#### Dashboard 3: Métricas de Negocio
**Paneles**:
- Consultas de clima por ciudad (gráfico de barras)
- Tasa de guardado de datos (gráfico de líneas)
- Ciudades más consultadas (gráfico de pie)
- Tendencias de consultas (gráfico de líneas con predicción)

#### Dashboard 4: SRE y Confiabilidad
**Paneles**:
- Availability % (SLO: 99.9%, línea de referencia)
- Error budget restante (gráfico de área)
- MTTR (Mean Time To Recovery)
- MTBF (Mean Time Between Failures)
- Alertas activas (tabla)

#### Dashboard 5: Análisis de Errores
**Paneles**:
- Errores por tipo (gráfico de barras)
- Errores por servicio (gráfico de barras)
- Timeline de errores (gráfico de líneas)
- Trace de error más reciente (panel de trace)
- Logs de errores (panel de logs)

### 11.4 Diagramas de Flujo de Problemas

#### Diagrama: Proceso de Diagnóstico de Problemas
**Pasos**:
1. Alerta recibida (Prometheus Alertmanager)
2. Verificar métricas (Prometheus)
3. Buscar traces relacionados (Tempo/Grafana)
4. Revisar logs correlacionados (Loki/Grafana)
5. Identificar root cause
6. Aplicar remediación
7. Verificar resolución

#### Diagrama: Escalado Automático
**Flujo**:
1. Métrica supera threshold (CPU > 70%)
2. HPA detecta condición
3. Calcula réplicas necesarias
4. Escala deployment
5. Nuevos pods se crean
6. Readiness probe verifica disponibilidad
7. Tráfico se distribuye a nuevos pods
8. Métricas vuelven a normal

### 11.5 Visualizaciones de Datos

#### Gráfico 1: Heatmap de Latencia
**Tipo**: Heatmap
**Eje X**: Tiempo (horas del día)
**Eje Y**: Endpoints
**Color**: Latencia (verde = bajo, rojo = alto)
**Uso**: Identificar patrones temporales de latencia

#### Gráfico 2: Service Graph
**Tipo**: Gráfico de red
**Nodos**: Servicios (micro-1, micro-2, api-gateway, postgres, openweathermap)
**Edges**: Llamadas entre servicios
**Tamaño de nodo**: Request rate
**Grosor de edge**: Latencia promedio
**Uso**: Visualizar dependencias y bottlenecks

#### Gráfico 3: Distribución de Latencia
**Tipo**: Histograma
**Eje X**: Latencia (buckets)
**Eje Y**: Frecuencia
**Líneas de referencia**: p50, p95, p99
**Uso**: Entender distribución de latencia, detectar outliers

#### Gráfico 4: Error Rate Timeline
**Tipo**: Gráfico de líneas apiladas
**Series**: Error rate por servicio
**Eje X**: Tiempo
**Eje Y**: Error rate (%)
**Uso**: Identificar correlaciones temporales de errores

---

## 12. Conclusiones y Recomendaciones

### 12.1 Fortalezas del Laboratorio

1. **Instrumentación Completa**: Los tres pilares (logs, traces, métricas) están implementados
2. **Estándares Abiertos**: Uso de OpenTelemetry garantiza portabilidad
3. **Correlación**: Trace_id vincula logs, traces y métricas
4. **Múltiples Lenguajes**: Demuestra implementación cross-language
5. **Service Mesh Integration**: Linkerd integrado correctamente
6. **Escalabilidad**: HPA y PDB configurados para alta disponibilidad

### 12.2 Oportunidades de Mejora

1. **Detección de Anomalías**: Implementar ML para detección automática
2. **Circuit Breakers**: Agregar para servicios externos
3. **Retry Logic**: Implementar retry con exponential backoff
4. **Cache**: Redis para reducir carga en API externa y BD
5. **Log Aggregation**: Configurar Loki para búsqueda de logs
6. **Alertas más Granulares**: Alertas por endpoint, no solo servicio
7. **SLO Dashboard**: Dashboard dedicado a SLOs y error budgets
8. **Distributed Tracing Avanzado**: Implementar sampling adaptativo

### 12.3 Mejores Prácticas Demostradas

1. **Semantic Conventions**: Uso consistente de atributos estándar
2. **Context Propagation**: Propagación correcta de trace context
3. **Error Handling**: Captura estructurada de errores con contexto
4. **Resource Management**: Límites y requests configurados apropiadamente
5. **Health Checks**: Readiness y liveness probes implementados
6. **Structured Logging**: Logs con formato JSON y correlación

### 12.4 Lecciones Aprendidas

1. **Observabilidad es más que métricas**: Traces y logs son esenciales para debugging
2. **Correlación es clave**: Trace_id permite conectar eventos dispersos
3. **Estándares ayudan**: OpenTelemetry facilita implementación multi-language
4. **Alertas proactivas**: Alertar antes de fallos críticos mejora MTTR
5. **Instrumentación temprana**: Agregar observabilidad desde el inicio es más fácil

---

## 13. Referencias y Recursos

### 13.1 Documentación Oficial
- [OpenTelemetry Documentation](https://opentelemetry.io/docs/)
- [Grafana Tempo Documentation](https://grafana.com/docs/tempo/latest/)
- [Prometheus Documentation](https://prometheus.io/docs/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)

### 13.2 Especificaciones
- [OpenTelemetry Semantic Conventions](https://opentelemetry.io/docs/specs/semconv/)
- [OpenTelemetry Protocol (OTLP)](https://opentelemetry.io/docs/specs/otlp/)
- [SRE Book](https://sre.google/sre-book/table-of-contents/)

### 13.3 Herramientas
- [OpenTelemetry Collector](https://opentelemetry.io/docs/collector/)
- [Grafana](https://grafana.com/docs/grafana/latest/)
- [Linkerd](https://linkerd.io/)

### 13.4 Documentación del Proyecto
- [Guía de Instrumentación](./INSTRUMENTACION.md): Configuración del SDK, métricas personalizadas, logs y flujo de trazas
- [Flujo OpenTelemetry → Tempo](./FLUJO_OTEL_TEMPO.md): Detalles técnicos de comunicación
- [Operaciones](./OPERACIONES.md): Comandos y guías operacionales

---

**Documento generado para análisis y presentación**
**Última actualización**: 2024
**Versión**: 1.0

