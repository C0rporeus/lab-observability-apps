# 🔧 Orquestación de Trazas con Atributos OpenTelemetry SDK
## Guía de Atributos Semánticos y Contexto Distribuido

**Documento Técnico de Orquestación de Trazas**
*Atributos del SDK, Propagación de Contexto y Correlación de Trazas Distribuidas*

---

## 📋 Tabla de Contenidos

1. [Atributos Semánticos del SDK](#1-atributos-semánticos-del-sdk)
2. [Propagación de Contexto entre Servicios](#2-propagación-de-contexto-entre-servicios)
3. [Flujo de Trazas Distribuidas](#3-flujo-de-trazas-distribuidas)
4. [Atributos de Resource](#4-atributos-de-resource)
5. [Atributos de Span](#5-atributos-de-span)
6. [Correlación de Logs con Trazas](#6-correlación-de-logs-con-trazas)
7. [Configuración del Collector](#7-configuración-del-collector)

---

## 1. Atributos Semánticos del SDK

### 1.1 Concepto de Atributos

Los atributos del SDK de OpenTelemetry son pares clave-valor que proporcionan contexto semántico sobre las operaciones, recursos y señales de telemetría. Estos atributos permiten:

- **Identificar servicios**: Atributos de resource como `service.name`, `service.version`
- **Contextualizar operaciones**: Atributos de span como `rpc.method`, `http.route`, `db.operation`
- **Correlacionar trazas**: Atributos de correlación como `trace.id`, `span.id`
- **Enriquecer métricas**: Atributos de dimensión como `endpoint`, `method`, `status_code`

### 1.2 Categorías de Atributos

#### Atributos de Resource (Nivel de Servicio)

Estos atributos se establecen una vez al inicializar el SDK y se aplican a todas las señales generadas por el servicio:

| Atributo | Descripción | Ejemplo | Estándar |
|----------|-------------|---------|----------|
| `service.name` | Nombre del servicio | `micro-1`, `micro-2`, `api-gateway` | ✅ Semántico |
| `service.version` | Versión del servicio | `1.0.0`, `2.5` | ✅ Semántico |
| `service.language` | Lenguaje de programación | `rust`, `go`, `nodejs` | ✅ Semántico |
| `telemetry.sdk.name` | Nombre del SDK | `opentelemetry` | ✅ Semántico |
| `telemetry.sdk.language` | Lenguaje del SDK | `rust`, `go`, `nodejs` | ✅ Semántico |
| `telemetry.sdk.version` | Versión del SDK | `0.25.0`, `1.38.0` | ✅ Semántico |
| `application` | Identificador de aplicación | `lab-observability` | ⚙️ Personalizado |

**Configuración por Servicio**:
- **micro-1 (Rust)**: `service.name=micro-1`, `service.language=rust`
- **micro-2 (Go)**: `service.name=micro-2`, `service.language=go`, `service.version=1.0.0`
- **api-gateway (Node.js)**: `service.name=api-gateway`, `service.language=nodejs`

#### Atributos de Span (Nivel de Operación)

Estos atributos se agregan a cada span individual y proporcionan contexto específico de la operación:

**Atributos RPC (gRPC)**:
- `rpc.system`: Sistema RPC (`grpc`)
- `rpc.method`: Nombre del método (`GetWeather`, `SaveWeatherData`)
- `rpc.service`: Nombre del servicio (`helloworld.Greeter`, `micro.MicroService`)

**Atributos HTTP**:
- `http.method`: Método HTTP (`GET`, `POST`)
- `http.route`: Ruta del endpoint (`/weather/micro2`)
- `http.url`: URL completa de la solicitud
- `http.status_code`: Código de estado HTTP (`200`, `404`, `500`)

**Atributos de Base de Datos**:
- `db.system`: Sistema de base de datos (`postgresql`)
- `db.name`: Nombre de la base de datos (`observability`)
- `db.operation`: Operación realizada (`SELECT`, `INSERT`)
- `db.statement`: Query SQL (opcional, puede ser truncado)

**Atributos de Negocio**:
- `weather.city`: Ciudad consultada (`Madrid`, `Barcelona`)
- `business.user_id`: ID de usuario (si aplica)
- `business.operation_type`: Tipo de operación (`weather_query`, `data_save`)

**Atributos de Response**:
- `response.success`: Indicador booleano de éxito (`true`, `false`)
- `error.message`: Mensaje de error (si aplica)
- `error.type`: Tipo de error (`api_error`, `db_error`, `timeout`)

---

## 2. Propagación de Contexto entre Servicios

### 2.1 Mecanismo de Propagación

La propagación de contexto permite que los servicios mantengan la continuidad de las trazas distribuidas mediante la inyección y extracción de información de seguimiento:

**Protocolo de Propagación**: W3C TraceContext
- Formato: `traceparent: 00-<trace-id>-<parent-span-id>-<flags>`
- Header HTTP: `traceparent`
- Header gRPC Metadata: `traceparent`

### 2.2 Flujo de Propagación

#### Paso 1: API Gateway (Origen de la Traza)

Cuando el API Gateway recibe una solicitud HTTP:
- Crea un **span raíz** si no existe contexto previo
- Establece atributos de resource: `service.name=api-gateway`
- Establece atributos de span: `http.method`, `http.route`, `http.url`
- Genera `trace_id` único y `span_id` inicial

**Atributos Establecidos**:
```
service.name: "api-gateway"
http.method: "GET"
http.route: "/weather/micro2"
trace_id: "abc123def456..."
span_id: "span1..."
```

#### Paso 2: Inyección de Contexto en gRPC Metadata

Antes de llamar a micro-2, el API Gateway:
- Inyecta el contexto usando el propagador del SDK
- Incluye `traceparent` en los headers de metadata gRPC
- Preserva el `trace_id` original
- Establece el `parent_span_id` como el span actual

**Headers Inyectados**:
```
traceparent: 00-abc123def456-span1-01
```

#### Paso 3: Extracción de Contexto en micro-2

El servicio micro-2:
- Extrae el contexto desde los headers gRPC metadata
- Recupera el `trace_id` propagado
- Identifica el `parent_span_id`
- Crea un **span hijo** con el mismo `trace_id`
- Establece atributos de resource: `service.name=micro-2`

**Atributos Establecidos**:
```
service.name: "micro-2"
rpc.system: "grpc"
rpc.method: "GetWeather"
trace_id: "abc123def456..." (propagado)
parent_span_id: "span1..." (del API Gateway)
span_id: "span2..." (nuevo)
```

#### Paso 4: Span Hijo para Llamada Externa

Cuando micro-2 llama a OpenWeatherMap API:
- Crea un **span hijo** adicional con el mismo `trace_id`
- Utiliza un TracerProvider diferenciado para visualización
- Establece `service.name=openweathermap-api` (diferente al servicio principal)
- Mantiene la relación padre-hijo con `parent_span_id=span2`

**Atributos Establecidos**:
```
service.name: "openweathermap-api"
http.method: "GET"
http.route: "/weather"
trace_id: "abc123def456..." (mismo)
parent_span_id: "span2..." (de micro-2)
span_id: "span3..." (nuevo)
```

### 2.3 Atributos de Correlación

Los atributos de correlación permiten vincular logs, métricas y traces:

| Atributo | Tipo | Descripción | Ubicación |
|----------|------|-------------|-----------|
| `trace.id` | String | Identificador único del trace completo | Span, Log |
| `span.id` | String | Identificador único del span | Span, Log |
| `trace.flags` | String | Flags de trace (`01` = sampled) | Span, Log |
| `parent_span_id` | String | ID del span padre (implícito en estructura) | Span |

**En Spans**: Estos atributos están implícitos en la estructura del span (no se agregan como atributos explícitos, pero están disponibles en el `SpanContext`).

**En Logs**: Se agregan explícitamente como atributos para correlación:
- `trace.id`: Para filtrar logs por trace
- `span.id`: Para filtrar logs por span específico
- `trace.flags`: Para identificar si el trace fue muestreado

---

## 3. Flujo de Trazas Distribuidas

### 3.1 Ejemplo Completo: GET `/weather/micro2?city=Madrid`

#### Arquitectura de Trazas

```
┌─────────────────────────────────────────────────────────────────┐
│ Trace ID: abc123def456...                                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Span 1: API Gateway (Raíz)                                    │
│  ├─ service.name: "api-gateway"                                │
│  ├─ http.method: "GET"                                          │
│  ├─ http.route: "/weather/micro2"                              │
│  ├─ http.url: "http://api-gateway:3000/weather/micro2?city=..."│
│  ├─ span_id: "span1..."                                        │
│  └─ trace_id: "abc123def456..."                                │
│      │                                                          │
│      ├─ [Propagación: traceparent en gRPC metadata]            │
│      │                                                          │
│      └─> Span 2: micro-2 (gRPC Handler)                        │
│          ├─ service.name: "micro-2"                            │
│          ├─ rpc.system: "grpc"                                 │
│          ├─ rpc.method: "GetWeather"                           │
│          ├─ weather.city: "Madrid"                             │
│          ├─ parent_span_id: "span1..." (Span 1)               │
│          ├─ span_id: "span2..."                               │
│          └─ trace_id: "abc123def456..." (propagado)           │
│              │                                                  │
│              └─> Span 3: OpenWeatherMap API (HTTP)             │
│                  ├─ service.name: "openweathermap-api"         │
│                  ├─ http.method: "GET"                         │
│                  ├─ http.route: "/weather"                     │
│                  ├─ parent_span_id: "span2..." (Span 2)       │
│                  ├─ span_id: "span3..."                       │
│                  └─ trace_id: "abc123def456..." (mismo)       │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 3.2 Establecimiento de Atributos por Servicio

#### micro-1 (Rust)

**Atributos de Resource**:
- `service.name`: `micro-1`
- `service.language`: `rust`
- `telemetry.sdk.name`: `opentelemetry`
- `telemetry.sdk.language`: `rust`

**Atributos de Span Comunes**:
- `rpc.system`: `grpc`
- `rpc.method`: Nombre del método (`GetWeather`, `SaveWeatherData`, `GetWeatherHistory`)
- `weather.city`: Ciudad consultada (cuando aplica)
- `db.system`: `postgresql` (en operaciones de BD)
- `db.operation`: Operación SQL (`SELECT`, `INSERT`)

#### micro-2 (Go)

**Atributos de Resource**:
- `service.name`: `micro-2`
- `service.version`: `1.0.0`
- `service.language`: `go`

**TracerProviders Diferenciados**:
- **TracerProvider Principal**: Para spans del servicio micro-2
  - `service.name`: `micro-2`
- **WeatherTracerProvider**: Para spans de llamadas a API externa
  - `service.name`: `openweathermap-api`
  - Permite visualización diferenciada en herramientas de observabilidad
- **DBTracerProvider**: Para spans de operaciones de base de datos
  - `service.name`: `postgres`
  - `db.system`: `postgresql`

**Atributos de Span Comunes**:
- `rpc.system`: `grpc`
- `rpc.method`: Nombre del método
- `weather.city`: Ciudad consultada
- `http.method`: `GET` (en llamadas HTTP externas)
- `http.route`: Ruta del endpoint externo

#### api-gateway (Node.js)

**Atributos de Resource**:
- `service.name`: `api-gateway`
- `service.language`: `nodejs`
- `application`: `lab-observability`

**Atributos de Span Comunes**:
- `http.method`: Método HTTP (`GET`, `POST`)
- `http.route`: Ruta del endpoint (`/weather/micro1`, `/weather/micro2`)
- `http.url`: URL completa con query parameters
- `http.status_code`: Código de respuesta (`200`, `500`, etc.)

### 3.3 Preservación de Contexto en Operaciones Asíncronas

Cuando los servicios realizan operaciones asíncronas (como llamadas HTTP o consultas a BD), el SDK:

1. **Preserva el Contexto**: El contexto del span padre se pasa a las operaciones hijas
2. **Mantiene trace_id**: Todas las operaciones hijas comparten el mismo `trace_id`
3. **Establece parent_span_id**: Cada span hijo referencia su span padre
4. **Enriquece con Atributos**: Cada operación agrega atributos específicos según su tipo

**Ejemplo de Flujo**:
```
Operación Principal → Async Operación 1 → Async Operación 2
    (trace_id: abc)      (trace_id: abc)    (trace_id: abc)
                        (parent: main)     (parent: main o async1)
```

---

## 4. Atributos de Resource

### 4.1 Propósito

Los atributos de resource proporcionan información sobre la entidad que genera las señales de telemetría (servicio, aplicación, infraestructura). Estos atributos se establecen una vez al inicializar el SDK y se aplican automáticamente a todas las señales.

### 4.2 Atributos Semánticos Estándar

| Atributo | Tipo | Descripción | Ejemplo |
|----------|------|-------------|---------|
| `service.name` | String | Nombre del servicio | `micro-1`, `micro-2`, `api-gateway` |
| `service.version` | String | Versión del servicio | `1.0.0`, `2.5` |
| `service.namespace` | String | Namespace del servicio | `production`, `staging` |
| `service.instance.id` | String | ID de instancia única | UUID del pod/container |
| `deployment.environment` | String | Ambiente de despliegue | `production`, `development` |

### 4.3 Atributos de Telemetría SDK

| Atributo | Tipo | Descripción | Ejemplo |
|----------|------|-------------|---------|
| `telemetry.sdk.name` | String | Nombre del SDK | `opentelemetry` |
| `telemetry.sdk.language` | String | Lenguaje del SDK | `rust`, `go`, `nodejs` |
| `telemetry.sdk.version` | String | Versión del SDK | `0.25.0`, `1.38.0` |

### 4.4 Uso en Orquestación

Los atributos de resource permiten:

- **Filtrar por servicio**: En herramientas de observabilidad, filtrar trazas por `service.name`
- **Agrupar por versión**: Identificar diferencias entre versiones del mismo servicio
- **Diferenciar servicios externos**: Como `openweathermap-api` vs `micro-2` en la misma traza
- **Correlacionar con infraestructura**: Relacionar señales con pods, containers, nodos

**Ejemplo de Filtrado**:
- Todas las trazas con `service.name=micro-2`
- Todas las trazas con `service.name=openweathermap-api`
- Trazas que incluyen tanto `micro-2` como `openweathermap-api` (traza distribuida completa)

---

## 5. Atributos de Span

### 5.1 Tipos de Atributos de Span

Los atributos de span se agregan a nivel de operación individual y proporcionan contexto específico sobre la acción realizada.

#### Atributos de Sistema

**RPC (gRPC)**:
- `rpc.system`: `grpc`
- `rpc.service`: Nombre del servicio gRPC (`helloworld.Greeter`, `micro.MicroService`)
- `rpc.method`: Nombre del método (`GetWeather`, `SaveWeatherData`)

**HTTP**:
- `http.method`: Método HTTP (`GET`, `POST`, `PUT`, `DELETE`)
- `http.route`: Ruta del endpoint (`/weather/micro2`)
- `http.url`: URL completa
- `http.status_code`: Código de estado (`200`, `404`, `500`)
- `http.request.header.*`: Headers de request (opcional)
- `http.response.header.*`: Headers de response (opcional)

**Base de Datos**:
- `db.system`: Sistema de BD (`postgresql`, `mysql`, `mongodb`)
- `db.name`: Nombre de la base de datos (`observability`)
- `db.operation`: Operación (`SELECT`, `INSERT`, `UPDATE`, `DELETE`)
- `db.statement`: Query SQL (puede ser truncado por seguridad)
- `db.sql.table`: Tabla afectada (`weather_data`)

#### Atributos de Negocio

Estos atributos son personalizados según el dominio de la aplicación:

- `weather.city`: Ciudad consultada (`Madrid`, `Barcelona`)
- `business.user_id`: ID de usuario (si aplica)
- `business.operation_type`: Tipo de operación (`weather_query`, `data_save`)
- `business.request_id`: ID de request interno (opcional)

#### Atributos de Estado

- `response.success`: `true` o `false`
- `error.message`: Mensaje de error si aplica
- `error.type`: Tipo de error (`api_error`, `db_error`, `timeout`, `validation_error`)
- `error.stack`: Stack trace completo (solo en casos de error)

### 5.2 Orquestación Mediante Atributos

Los atributos permiten:

1. **Identificar Rutas de Request**: Filtrar por `http.route` o `rpc.method`
2. **Análisis de Rendimiento**: Agrupar por `weather.city` para ver qué ciudades tienen más latencia
3. **Debugging de Errores**: Filtrar por `error.type` y `error.message`
4. **Correlación de Operaciones**: Buscar todas las operaciones con mismo `business.request_id`
5. **Análisis de Dependencias**: Identificar servicios externos por `service.name` en spans anidados

**Ejemplo de Consulta**:
```
Buscar todas las trazas donde:
- service.name = "micro-2"
- rpc.method = "GetWeather"
- weather.city = "Madrid"
- error.type existe (solo errores)
```

---

## 6. Correlación de Logs con Trazas

### 6.1 Atributos de Correlación en Logs

Los logs incluyen atributos de correlación para vincularlos con las trazas correspondientes:

| Atributo | Tipo | Descripción | Origen |
|----------|------|-------------|--------|
| `trace.id` | String | ID del trace completo | `SpanContext.trace_id()` |
| `span.id` | String | ID del span actual | `SpanContext.span_id()` |
| `trace.flags` | String | Flags del trace (`01` = sampled) | `SpanContext.trace_flags()` |

### 6.2 Estructura de Log Estructurado

**Formato JSON estándar**:

```json
{
  "timestamp": "2024-01-15T10:30:45.123Z",
  "level": "INFO|WARN|ERROR",
  "message": "Weather retrieved successfully for Madrid",
  "service.name": "micro-2",
  "trace.id": "abc123def456...",
  "span.id": "span2...",
  "trace.flags": "01",
  "weather.city": "Madrid",
  "duration_ms": 150
}
```

### 6.3 Beneficios de la Correlación

- **Navegación desde Logs a Trazas**: Click en `trace.id` en un log → ver traza completa
- **Filtrado de Logs por Trace**: Ver todos los logs de una traza específica
- **Análisis de Flujo Completo**: Entender qué pasó en cada servicio durante una request
- **Debugging Distribuido**: Identificar en qué servicio ocurrió un error y ver el contexto completo

### 6.4 Enriquecimiento Automático

El SDK automáticamente:
- Extrae `trace.id` y `span.id` del span activo en el contexto
- Los agrega como atributos a los logs cuando están disponibles
- Mantiene la relación incluso si el log se genera en una operación asíncrona

**Ejemplo de Logs Correlacionados**:
```
[API Gateway] trace.id=abc123, span.id=span1: "Received GET /weather/micro2"
[API Gateway] trace.id=abc123, span.id=span1: "Calling micro-2 gRPC"
[micro-2] trace.id=abc123, span.id=span2: "Processing GetWeather for Madrid"
[micro-2] trace.id=abc123, span.id=span3: "Calling OpenWeatherMap API"
[micro-2] trace.id=abc123, span.id=span3: "Received weather data"
[micro-2] trace.id=abc123, span.id=span2: "Weather retrieved successfully"
[API Gateway] trace.id=abc123, span.id=span1: "Response sent to client"
```

Todos estos logs comparten el mismo `trace.id`, permitiendo reconstruir el flujo completo.

---

## 7. Configuración del Collector

### 7.1 Receivers (Receptores)

El collector recibe señales en múltiples protocolos:

**OTLP gRPC** (Puerto 4317):
- Traces y métricas de micro-1 (Rust) y micro-2 (Go)
- Protocolo: gRPC binario

**OTLP HTTP** (Puerto 4318):
- Traces y logs de micro-3 (Node.js)
- Métricas de todos los servicios
- Endpoints:
  - `/v1/traces`: Traces
  - `/v1/metrics`: Métricas
  - `/v1/logs`: Logs

### 7.2 Processors (Procesadores)

Los processors permiten enriquecer, filtrar y transformar las señales:

**Batch Processor**:
- Agrupa señales en batches para exportación eficiente
- Configuración: `timeout: 10s`, `send_batch_size: 512`

**Memory Limiter**:
- Previene consumo excesivo de memoria
- Configuración: `limit_mib: 1000`, `spike_limit_mib: 500`

**Resource Processor**:
- Agrega atributos de resource adicionales
- Ejemplo: `environment: production` a todas las señales

### 7.3 Exporters (Exportadores)

Los exporters envían las señales procesadas a sistemas de observabilidad:

**Jaeger** (Traces):
- Endpoint: `http://jaeger:4317`
- Formato: OTLP gRPC

**Loki** (Logs):
- Endpoint: `http://loki:3100/otlp`
- Formato: OTLP HTTP

**Prometheus** (Métricas):
- Endpoint: `0.0.0.0:8889`
- Formato: OpenMetrics / Prometheus text format
- Scrape por Prometheus configurado

**Tempo** (Traces alternativo):
- Endpoint configurado para almacenamiento de traces distribuidos

### 7.4 Service Pipelines

Los pipelines definen el flujo de procesamiento:

**Pipeline de Traces**:
```
Receivers: [otlp]
  ↓
Processors: [batch, memory_limiter, resource]
  ↓
Exporters: [otlp/jaeger, otlp/tempo, debug]
```

**Pipeline de Logs**:
```
Receivers: [otlp]
  ↓
Processors: [batch, memory_limiter, resource]
  ↓
Exporters: [otlphttp/loki, debug]
```

**Pipeline de Métricas**:
```
Receivers: [otlp, prometheus]
  ↓
Processors: [batch, memory_limiter, resource]
  ↓
Exporters: [prometheus, debug]
```

### 7.5 Preservación de Atributos

El collector preserva todos los atributos establecidos por los SDKs:

- **Atributos de Resource**: Se mantienen intactos (`service.name`, `service.version`, etc.)
- **Atributos de Span**: Se exportan a Jaeger/Tempo con todos los atributos originales
- **Atributos de Log**: Se incluyen en los logs exportados a Loki
- **Metadata de Correlación**: `trace.id`, `span.id` se mantienen para correlación

El collector puede agregar atributos adicionales (como `environment`), pero nunca elimina atributos establecidos por las aplicaciones.

---

## 8. Buenas Prácticas de Orquestación

### 8.1 Establecimiento Consistente de Atributos

- **Usar Atributos Semánticos**: Preferir atributos estándar (`rpc.method`, `http.route`) sobre personalizados cuando sea posible
- **Nomenclatura Consistente**: Usar la misma convención de nombres en todos los servicios
- **Valores Normalizados**: Usar valores consistentes (ej: `weather.city` siempre en mayúsculas o siempre en minúsculas)

### 8.2 Propagación de Contexto

- **Siempre Inyectar**: Inyectar contexto antes de cada llamada entre servicios
- **Siempre Extraer**: Extraer contexto al recibir solicitudes de otros servicios
- **Preservar Trace ID**: No generar nuevos trace IDs en servicios intermedios
- **Mantener Parent References**: Establecer correctamente `parent_span_id`

### 8.3 Enriquecimiento de Atributos

- **Agregar Contexto Relevante**: Incluir atributos que ayuden a filtrar y analizar trazas
- **Evitar Información Sensible**: No incluir datos sensibles en atributos (passwords, tokens)
- **Limitar Cardinalidad**: Evitar atributos con valores únicos muy altos (como UUIDs) que dificultan el análisis

### 8.4 Correlación de Señales

- **Incluir trace.id en Logs**: Siempre incluir `trace.id` y `span.id` en logs estructurados
- **Referenciar trace.id en Métricas**: Agregar `trace.id` como tag en métricas cuando sea relevante
- **Mantener Relación Temporal**: Logs y spans deben tener timestamps consistentes

---

## 9. Endpoints Disponibles

### 9.1 API Gateway (HTTP - Puerto 3000)

#### Endpoints de Salud
- `GET /health`: Estado de salud del API Gateway
- `GET /metrics`: Métricas en formato Prometheus

#### Endpoints de Microservicios
- `GET /micro1`: Ping a micro-1 (Rust)
- `GET /micro2`: Ping a micro-2 (Go)

#### Endpoints de Clima - micro-1 (Rust)
- `GET /weather/micro1?city={city}`: Consulta clima desde API externa
- `GET /weather/micro1/history/{limit}`: Historial general (todas las ciudades)
- `GET /weather/micro1/history/{city}/{limit}`: Historial por ciudad específica

#### Endpoints de Clima - micro-2 (Go)
- `GET /weather/micro2?city={city}`: Consulta clima desde API externa
- `POST /weather/micro2/save`: Guarda datos meteorológicos en BD
- `GET /weather/micro2/history/all/{limit}`: Historial general (todas las ciudades)
- `GET /weather/micro2/history/{city}/{limit}`: Historial por ciudad específica

### 9.2 micro-1 (gRPC - Puerto 50051)

**Servicio**: `helloworld.Greeter`

| Método gRPC | Descripción |
|-------------|-------------|
| `SendMessage` | Envía mensaje y recibe respuesta |
| `GetHelloWorld` | Retorna saludo "Hello World!" |
| `GetWeather` | Consulta clima de una ciudad |
| `SaveWeatherData` | Guarda datos meteorológicos |
| `GetWeatherHistory` | Obtiene historial meteorológico |

### 9.3 micro-2 (gRPC - Puerto 50051)

**Servicio**: `micro.MicroService`

| Método gRPC | Descripción |
|-------------|-------------|
| `Ping` | Ping de prueba |
| `GetWeather` | Consulta clima de una ciudad |
| `SaveWeatherData` | Guarda datos meteorológicos en BD |
| `GetWeatherHistory` | Obtiene historial meteorológico |

### 9.4 Flujo de Trazas por Endpoint

**Ejemplo: GET `/weather/micro2?city=Madrid`**

```
1. Cliente HTTP → API Gateway
   ├─ Span: Raíz con http.route="/weather/micro2"
   ├─ service.name: "api-gateway"
   └─ trace_id: abc123

2. API Gateway → micro-2 (gRPC)
   ├─ Span: Hijo con rpc.method="GetWeather"
   ├─ service.name: "micro-2"
   ├─ parent_span_id: span1 (del API Gateway)
   └─ trace_id: abc123 (propagado)

3. micro-2 → OpenWeatherMap API (HTTP)
   ├─ Span: Hijo con http.method="GET"
   ├─ service.name: "openweathermap-api"
   ├─ parent_span_id: span2 (de micro-2)
   └─ trace_id: abc123 (mismo)

4. Respuesta propagada hacia atrás
   └─ Todos los spans finalizan con éxito
```

---

## 10. Variables de Entorno

### Variables Comunes

| Variable | Descripción | Valor por Defecto |
|----------|-------------|-------------------|
| `OTEL_SERVICE_NAME` | Nombre del servicio | `micro-1`, `micro-2`, `api-gateway` |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | Endpoint del collector | `http://otel-collector:4317` |
| `OTEL_EXPORTER_OTLP_PROTOCOL` | Protocolo OTLP | `grpc` o `http/protobuf` |

### Variables Específicas por Servicio

#### micro-1 (Rust)
- `DB_HOST`: Host de PostgreSQL (default: `postgres`)
- `DB_PORT`: Puerto de PostgreSQL (default: `5432`)
- `DB_USER`: Usuario de PostgreSQL (default: `postgres`)
- `DB_PASSWORD`: Contraseña de PostgreSQL
- `DB_NAME`: Nombre de la base de datos (default: `observability`)
- `WEATHER_API_KEY`: API key de OpenWeatherMap (requerido)

#### micro-2 (Go)
- Mismas variables de base de datos que micro-1
- `WEATHER_API_KEY`: API key de OpenWeatherMap (requerido)

#### micro-3 (API Gateway)
- No requiere variables adicionales (endpoints configurados internamente)

---

## 11. Referencias

- [OpenTelemetry Documentation](https://opentelemetry.io/docs/)
- [OpenTelemetry Semantic Conventions](https://opentelemetry.io/docs/specs/semconv/)
- [OpenTelemetry Protocol (OTLP)](https://opentelemetry.io/docs/specs/otlp/)
- [W3C TraceContext Specification](https://www.w3.org/TR/trace-context/)

---

**Documento generado para referencia técnica de orquestación de trazas**
**Última actualización**: 2024
**Versión**: 2.0
