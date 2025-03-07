#!/bin/bash
# filepath: /home/f3nr1r/Documentos/projects/lab-observability-apps/install-go-deps.sh

set -e

echo "Instalando dependencias de Go para micro-2..."

cd micro-2

# Inicializar módulo Go si no existe
if [ ! -f "go.mod" ]; then
  echo "Inicializando módulo Go..."
  go mod init micro-2
fi

OTEL_VERSION="v1.19.0"

echo "Instalando dependencias básicas..."
go get go.opentelemetry.io/otel@$OTEL_VERSION
go get go.opentelemetry.io/otel/attribute@$OTEL_VERSION
go get go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc@$OTEL_VERSION
go get go.opentelemetry.io/otel/sdk/resource@$OTEL_VERSION
go get go.opentelemetry.io/otel/sdk/trace@$OTEL_VERSION
go get go.opentelemetry.io/otel/trace@$OTEL_VERSION
go get google.golang.org/grpc

echo "Instalando dependencias adicionales..."
go get go.opentelemetry.io/otel/semconv/v1.17.0@$OTEL_VERSION
go get google.golang.org/grpc/credentials/insecure
go get go.opentelemetry.io/otel/propagation@$OTEL_VERSION

echo "Actualizando go.mod..."
go mod tidy

echo "Dependencias instaladas correctamente:"
go list -m all | grep opentelemetry

echo "Ahora necesitas actualizar main.go para usar las nuevas dependencias"