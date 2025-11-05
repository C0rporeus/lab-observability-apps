#!/bin/bash
set -e

# Configurar Docker según el entorno
if command -v minikube > /dev/null 2>&1 && minikube status > /dev/null 2>&1; then
    echo "📦 Configurando Docker para minikube..."
    eval $(minikube docker-env)
else
    echo "📦 Usando Docker Desktop (o Docker local)"
    # No necesitamos configuración adicional para Docker Desktop
fi

echo "Construyendo imagen de micro-1 (Rust)..."

docker build -t localhost:5000/micro-1:latest ./micro-1

echo "Construyendo imagen de micro-2 (Go)..."

docker build -t localhost:5000/micro-2:latest ./micro-2

echo "Construyendo imagen de micro-3 (TypeScript)..."
docker build -t localhost:5000/api-gateway:latest ./micro-3

echo "Imágenes construidas correctamente"
docker image ls