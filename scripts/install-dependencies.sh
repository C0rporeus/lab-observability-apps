#!/bin/bash
set -e

echo "🔧 Instalando dependencias necesarias para el lab de observabilidad..."

# Función para verificar si un comando existe
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Instalar step CLI
if ! command_exists step; then
    echo "📦 Instalando step CLI..."
    
    # Detectar el sistema operativo
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        if command_exists brew; then
            brew install step
        else
            echo "⚠️  Homebrew no encontrado. Instalando step manualmente..."
            # Descargar e instalar step para macOS
            curl -LO https://github.com/smallstep/cli/releases/latest/download/step_macos_amd64.tar.gz
            tar -xzf step_macos_amd64.tar.gz
            sudo mv step_*/bin/step /usr/local/bin/
            rm -rf step_* step_macos_amd64.tar.gz
        fi
    else
        # Linux - usar el archivo .deb que ya tienes
        echo "📦 Instalando step CLI desde el archivo .deb..."
        if [ -f "step-cli_amd64.deb" ]; then
            sudo dpkg -i step-cli_amd64.deb || sudo apt-get install -f
        else
            echo "❌ No se encontró step-cli_amd64.deb"
            exit 1
        fi
    fi
    
    echo "✅ step CLI instalado correctamente"
else
    echo "✅ step CLI ya está instalado"
fi

# Instalar Linkerd CLI
if ! command_exists linkerd; then
    echo "📦 Instalando Linkerd CLI..."
    
    # Detectar el sistema operativo para Linkerd
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        curl -sL https://run.linkerd.io/install | sh
        export PATH=$PATH:$HOME/.linkerd2/bin
        echo 'export PATH=$PATH:$HOME/.linkerd2/bin' >> ~/.zshrc
    else
        # Linux
        curl -sL https://run.linkerd.io/install | sh
        export PATH=$PATH:$HOME/.linkerd2/bin
        echo 'export PATH=$PATH:$HOME/.linkerd2/bin' >> ~/.bashrc
    fi
    
    echo "✅ Linkerd CLI instalado correctamente"
    echo "🔄 Por favor, recarga tu terminal o ejecuta: source ~/.zshrc"
else
    echo "✅ Linkerd CLI ya está instalado"
fi

# Verificar instalaciones
echo ""
echo "🔍 Verificando instalaciones..."

if command_exists step; then
    echo "✅ step CLI: $(step version | head -n1)"
else
    echo "❌ step CLI no está disponible"
fi

if command_exists linkerd; then
    echo "✅ Linkerd CLI: $(linkerd version --client | head -n1)"
else
    echo "❌ Linkerd CLI no está disponible"
fi

echo ""
echo "🎉 Dependencias instaladas correctamente!"
echo "🚀 Ahora puedes ejecutar: ./scripts/deploy-lab.sh"
