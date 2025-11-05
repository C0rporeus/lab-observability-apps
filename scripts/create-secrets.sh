#!/bin/bash
set -e

# Script para crear secret de Weather API Key desde archivo .env
# Uso: ./scripts/create-secrets.sh
# NOTA: Las credenciales de PostgreSQL están en postgres-deployment.yaml y se crean automáticamente

cd "$(dirname "$0")/.."

# Verificar que existe el archivo .env
if [ ! -f ".env" ]; then
    echo "❌ Error: No se encontró el archivo .env"
    echo "💡 Copia env.example a .env y configura la Weather API Key:"
    echo "   cp env.example .env"
    echo "   # Luego edita .env con tu Weather API Key real"
    exit 1
fi

# Cargar variables de entorno
set -a
source .env
set +a

# Verificar que la variable WEATHER_API_KEY está definida
if [ -z "$WEATHER_API_KEY" ] || [ "$WEATHER_API_KEY" = "YOUR_WEATHER_API_KEY_HERE" ]; then
    echo "❌ Error: La variable WEATHER_API_KEY debe estar definida en .env"
    echo "💡 Obtén tu API key en: https://openweathermap.org/api"
    exit 1
fi

echo "🔐 Creando secret de Weather API Key en Kubernetes..."

# Crear o actualizar secret de Weather API Key
kubectl create secret generic weather-api-key \
    --from-literal=WEATHER_API_KEY="${WEATHER_API_KEY}" \
    --dry-run=client -o yaml | kubectl apply -f -

echo "✅ Secret weather-api-key creado/actualizado correctamente"
echo "ℹ️  Las credenciales de PostgreSQL se gestionan mediante postgres-deployment.yaml"

