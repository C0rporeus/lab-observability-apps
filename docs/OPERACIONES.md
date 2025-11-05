# 🚀 Operaciones del Lab de Observabilidad

## 🛠️ Instalación y Configuración Inicial

### Primera Instalación Completa
Para instalar todo el stack de observabilidad desde cero:

```bash
# 1. Instalar dependencias (solo primera vez)
./install-dependencies.sh

# 2. Desplegar todo el laboratorio
./scripts/deploy-lab.sh
```

### Reinicio Después de Docker Desktop
Si reiniciaste Docker Desktop o minikube, ejecuta:

```bash
./start-lab.sh
```

Este script verifica y reinicia todos los componentes sin reinstalar desde cero.

## 📡 Port Forwarding de Componentes

### 1. API Gateway (Puerto 8080)
```bash
kubectl port-forward svc/api-gateway 8080:3000
```

### 2. Grafana (Puerto 3000)
```bash
kubectl port-forward svc/grafana 3000:3000
```

### 3. Tempo (Puerto 3200)
```bash
kubectl port-forward svc/tempo 3200:3200
```

### 4. Prometheus (Puerto 9090)
```bash
kubectl port-forward svc/prometheus 9090:9090
```

### 5. OpenTelemetry Collector Metrics (Puerto 8889)
```bash
kubectl port-forward svc/otel-collector 8889:8889
```
o 

Iniciar todos los port-forwards
```
./scripts/port-forward.sh start
```
Detener todos los port-forwards
```
./scripts/port-forward.sh stop
```
Ver el estado de los port-forwards
```
./scripts/port-forward.sh status
```

Reiniciar todos los port-forwards
```
./scripts/port-forward.sh restart
```
---

## 🌐 URLs de Acceso

Una vez configurados los port forwards:

| Componente | URL | Credenciales |
|------------|-----|--------------|
| Grafana | http://localhost:3000 | anonymous (Admin) |
| Tempo | http://localhost:3200 | - |
| Prometheus | http://localhost:9090 | - |
| API Gateway | http://localhost:8080 | - |

---

## 🔥 Generación de Tráfico para Observabilidad

### 📋 Resumen de Endpoints Disponibles

| Microservicio | Método | Endpoint | Descripción |
|---------------|--------|----------|-------------|
| **micro-2 (Go)** | GET | `/weather/micro2?city={city}` | Consulta clima desde API externa |
| **micro-2 (Go)** | POST | `/weather/micro2/save` | Guarda datos en base de datos |
| **micro-2 (Go)** | GET | `/weather/micro2/history/all/{limit}` | Historial general de todas las ciudades |
| **micro-2 (Go)** | GET | `/weather/micro2/history/{city}/{limit}` | Historial por ciudad específica |
| **micro-1 (Rust)** | GET | `/weather/micro1?city={city}` | Consulta clima desde API externa |
| **micro-1 (Rust)** | GET | `/weather/micro1/history/{limit}` | Historial general de todas las ciudades |
| **micro-1 (Rust)** | GET | `/weather/micro1/history/{city}/{limit}` | Historial por ciudad específica |

---

### 1️⃣ micro-2 (Go) - Consulta de Clima desde API Externa (GET)

**Consultar clima de Madrid:**
```bash
curl "http://localhost:8080/weather/micro2?city=Madrid" | jq '.'
```

**Consultar clima de Barcelona:**
```bash
curl "http://localhost:8080/weather/micro2?city=Barcelona" | jq '.'
```

**Consultar clima de Tokyo:**
```bash
curl "http://localhost:8080/weather/micro2?city=Tokyo" | jq '.'
```

**Consultar clima de Bogotá:**
```bash
curl "http://localhost:8080/weather/micro2?city=Bogota" | jq '.'
```

**Consultar clima de Amsterdam:**
```bash
curl "http://localhost:8080/weather/micro2?city=Amsterdam" | jq '.'
```

### 2️⃣ micro-2 (Go) - Escritura en Base de Datos (POST)

**Guardar datos meteorológicos en PostgreSQL:**
```bash
curl -X POST http://localhost:8080/weather/micro2/save \
  -H "Content-Type: application/json" \
  -d '{
    "city": "Madrid",
    "temperature": 15.5,
    "condition": "clear sky",
    "humidity": 65,
    "windSpeed": 3.5
  }' | jq '.'
```

**Guardar datos de Barcelona:**
```bash
curl -X POST http://localhost:8080/weather/micro2/save \
  -H "Content-Type: application/json" \
  -d '{
    "city": "Barcelona",
    "temperature": 18.2,
    "condition": "few clouds",
    "humidity": 70,
    "windSpeed": 4.2
  }' | jq '.'
```

**Guardar datos de Tokyo:**
```bash
curl -X POST http://localhost:8080/weather/micro2/save \
  -H "Content-Type: application/json" \
  -d '{
    "city": "Tokyo",
    "temperature": 22.1,
    "condition": "partly cloudy",
    "humidity": 68,
    "windSpeed": 2.8
  }' | jq '.'
```

### 3️⃣ micro-2 (Go) - Consulta General de Historial (GET)

**Consultar últimas 10 entradas (todas las ciudades):**
```bash
curl "http://localhost:8080/weather/micro2/history/all/10" | jq '.'
```

**Consultar últimas 5 entradas (todas las ciudades):**
```bash
curl "http://localhost:8080/weather/micro2/history/all/5" | jq '.'
```

### 4️⃣ micro-2 (Go) - Consulta de Historial por Ciudad (GET)

**Consultar historial de Madrid (últimas 5 entradas):**
```bash
curl "http://localhost:8080/weather/micro2/history/Madrid/5" | jq '.'
```

**Consultar historial de Barcelona (últimas 3 entradas):**
```bash
curl "http://localhost:8080/weather/micro2/history/Barcelona/3" | jq '.'
```

**Consultar historial de Tokyo (últimas 10 entradas):**
```bash
curl "http://localhost:8080/weather/micro2/history/Tokyo/10" | jq '.'
```

### 5️⃣ micro-1 (Rust) - Consultas desde micro-1

#### 5.1 Consulta de Clima desde API Externa (GET)

**Consultar clima de Madrid:**
```bash
curl "http://localhost:8080/weather/micro1?city=Madrid" | jq '.'
```

**Consultar clima de Barcelona:**
```bash
curl "http://localhost:8080/weather/micro1?city=Barcelona" | jq '.'
```

**Consultar clima de Paris:**
```bash
curl "http://localhost:8080/weather/micro1?city=Paris" | jq '.'
```

**Consultar clima de London:**
```bash
curl "http://localhost:8080/weather/micro1?city=London" | jq '.'
```

#### 5.2 Consulta General de Historial (GET)

**Consultar últimas 10 entradas (todas las ciudades):**
```bash
curl "http://localhost:8080/weather/micro1/history/10" | jq '.'
```

**Consultar últimas 5 entradas (todas las ciudades):**
```bash
curl "http://localhost:8080/weather/micro1/history/5" | jq '.'
```

#### 5.3 Consulta de Historial por Ciudad (GET)

**Consultar historial de Madrid (últimas 5 entradas):**
```bash
curl "http://localhost:8080/weather/micro1/history/Madrid/5" | jq '.'
```

**Consultar historial de Barcelona (últimas 3 entradas):**
```bash
curl "http://localhost:8080/weather/micro1/history/Barcelona/3" | jq '.'
```

**Consultar historial de Paris (últimas 10 entradas):**
```bash
curl "http://localhost:8080/weather/micro1/history/Paris/10" | jq '.'
```

---

## 📊 Escenarios de Observabilidad

### Escenario 1: Consulta de API Externa Completa

Este flujo genera trazas para:
- `api-gateway` (handling request)
- `micro-2` (GetWeather gRPC call)
- `openweathermap-api` (HTTP GET external API)

```bash
for city in Madrid Barcelona Tokyo Bogota London; do
  echo "Consultando clima de $city..."
  curl -s "http://localhost:8080/weather/micro2?city=$city" | jq -r '.temperature, .condition'
  sleep 2
done
```

### Escenario 2: Escritura y Lectura de Base de Datos

Este flujo genera trazas para:
- `api-gateway` (handling request)
- `micro-2` (SaveWeatherData gRPC call)
- `postgres` (INSERT query)

```bash
curl -X POST http://localhost:8080/weather/micro2/save \
  -H "Content-Type: application/json" \
  -d '{"city":"Rome","temperature":20.5,"condition":"sunny","humidity":60,"windSpeed":2.3}'

curl "http://localhost:8080/weather/micro2/history/Rome/5"
```

### Escenario 3: Lectura de Base de Datos

Este flujo genera trazas para:
- `api-gateway` (handling request)
- `micro-2` (GetWeatherHistory gRPC call)
- `postgres` (SELECT query)

```bash
curl "http://localhost:8080/weather/micro2/history/all/10"
```

### Escenario 4: Carga de Tráfico Mixta (micro-2)

Genera trazas variadas para observar el comportamiento del sistema:

```bash
# Generar carga variada
for i in {1..20}; do
  city=$(shuf -e Madrid Barcelona Tokyo London Paris Rome -n 1)
  if [ $((i % 3)) -eq 0 ]; then
    # 1/3 escrituras
    curl -s -X POST http://localhost:8080/weather/micro2/save \
      -H "Content-Type: application/json" \
      -d "{\"city\":\"$city\",\"temperature\":$((10 + RANDOM % 20)).$((RANDOM % 99)),\"condition\":\"test\",\"humidity\":$((50 + RANDOM % 30)),\"windSpeed\":$((RANDOM % 5)).$((RANDOM % 9))}" > /dev/null
    echo "✅ Guardado: $city"
  else
    # 2/3 consultas API
    curl -s "http://localhost:8080/weather/micro2?city=$city" > /dev/null
    echo "✅ Consultado: $city"
  fi
  sleep 1
done

# Consultar historial
echo "📊 Historial:"
curl -s "http://localhost:8080/weather/micro2/history/all/20" | jq '.count'
```

### Escenario 5: Consulta de API Externa con micro-1 (Rust)

Este flujo genera trazas para:
- `api-gateway` (handling request)
- `micro-1` (GetWeather gRPC call)
- `openweathermap-api` (HTTP GET external API)

```bash
for city in Madrid Barcelona Paris London Rome; do
  echo "Consultando clima de $city..."
  curl -s "http://localhost:8080/weather/micro1?city=$city" | jq -r '.temperature, .condition'
  sleep 2
done
```

### Escenario 6: Lectura de Historial con micro-1 (Rust)

Este flujo genera trazas para:
- `api-gateway` (handling request)
- `micro-1` (GetWeatherHistory gRPC call)
- `postgres` (SELECT query)

```bash
# Consultar historial general
curl "http://localhost:8080/weather/micro1/history/10"

# Consultar historial por ciudad
curl "http://localhost:8080/weather/micro1/history/Madrid/5"
```

---

## 🔍 Verificación de Observabilidad

### En Tempo
1. Abrir http://localhost:3200
2. Buscar trazas por servicio: `{ resource.service.name = "api-gateway" }`
3. Deberías ver:
   - Trazas de `api-gateway`
   - Hijos `micro-2` o `openweathermap-api`
   - Hijos `postgres` en queries DB

### En Grafana
1. Abrir http://localhost:3000
2. Dashboard: "Observability Stack - Overview"
3. Ver:
   - Métricas de request rate
   - Response time (p95)
   - Logs del API Gateway
   - Trazas distribuidas

### En Prometheus
1. Abrir http://localhost:9090
2. Query: `rate(otel_http_requests_total[5m])`
3. Ver métricas de OpenTelemetry

---

## 🎯 Resumen de Endpoints

| Método | Endpoint | Descripción | Servicios en Traza |
|--------|----------|-------------|-------------------|
| GET | `/weather/micro2?city=XXX` | Consulta API externa | api-gateway → micro-2 → openweathermap-api |
| POST | `/weather/micro2/save` | Guarda en DB | api-gateway → micro-2 → postgres |
| GET | `/weather/micro2/history/all/N` | Consulta todas las ciudades | api-gateway → micro-2 → postgres |
| GET | `/weather/micro2/history/CITY/N` | Consulta por ciudad | api-gateway → micro-2 → postgres |

---

## 🛠️ Troubleshooting

### Problema: "Connection refused" en port-forward
```bash
# Verificar que el pod está corriendo
kubectl get pods

# Reiniciar el port-forward
pkill -f "port-forward"
kubectl port-forward svc/<nombre-servicio> <puerto-local>:<puerto-pod>
```

### Problema: No aparecen métricas en Prometheus
```bash
# Verificar que Prometheus está scrapeando el collector
curl http://localhost:9090/api/v1/label/__name__/values | jq '.data[]' | grep otel

# Verificar logs del collector
kubectl logs -l app=opentelemetry-collector -c otel-collector
```

### Problema: Linkerd en CrashLoopBackOff
```bash
# Regenerar certificados y reinstalar
cd /Users/f3nr1r/Documents/projects/lab-observability-apps
./scripts/deploy-lab.sh
```

### Problema: Datos no aparecen en Jaeger
```bash
# Verificar que el collector está enviando trazas
kubectl logs -l app=opentelemetry-collector -c otel-collector --tail=100 | grep -i "traces"

# Verificar conectividad
kubectl exec -it <pod-otel-collector> -- nc -zv jaeger 4317
```

---

## 📝 Notas Importantes

1. **Separación de Servicios**: micro-2 usa múltiples TracerProviders para separar visualmente:
   - `micro-2`: Operaciones principales
   - `openweathermap-api`: API externa
   - `postgres`: Base de datos

2. **Certificados Linkerd**: Los certificados expiran cada 720 horas. Usar `start-lab.sh` para regenerarlos automáticamente.

3. **Logs**: Los logs están disponibles en Loki pero requieren configuración adicional de scraping.

4. **Dashboard Grafana**: El dashboard provisto es básico. Puedes importar dashboards más avanzados desde https://grafana.com/grafana/dashboards/

---

## 🎓 Aprendizajes Clave

- **Distributed Tracing**: Trazas end-to-end desde API Gateway hasta DB
- **Service Discrimination**: TracerProviders separados permiten diferenciar servicios visualmente
- **Correlación**: TraceID permite correlacionar logs, métricas y trazas
- **Span Nesting**: Contexto padre-hijo correctamente propagado
- **OpenTelemetry**: Estándar unificado para observabilidad

