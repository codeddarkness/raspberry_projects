#!/bin/bash

# Universal Open WebUI Installation Script
# Supports Debian/Ubuntu Linux and macOS Intel
# Integrates with existing Ollama installation

set -e

echo "=========================================="
echo "Universal Open WebUI Installation Script"
echo "For Linux and macOS with Ollama"
echo "=========================================="

# Detect OS
OS=""
DOCKER_CMD=""

case "$(uname -s)" in
    Linux*)
        OS="Linux"
        ;;
    Darwin*)
        OS="macOS"
        ;;
    *)
        echo "Unsupported operating system: $(uname -s)"
        exit 1
        ;;
esac

echo "Detected: $OS"

# Check if Ollama is installed and running
check_ollama() {
    if ! command -v ollama &> /dev/null; then
        echo "Error: Ollama not found. Please run the Ollama installation script first."
        exit 1
    fi

    # Try to start Ollama if not running
    if ! curl -s http://localhost:11434/api/tags > /dev/null; then
        echo "Starting Ollama..."
        if [ "$OS" = "Linux" ]; then
            if systemctl is-enabled ollama &> /dev/null; then
                sudo systemctl start ollama
            else
                ollama serve > /tmp/ollama.log 2>&1 &
            fi
        else
            ollama serve > /tmp/ollama.log 2>&1 &
        fi
        sleep 5
    fi

    # Verify Ollama is responding
    if ! curl -s http://localhost:11434/api/tags > /dev/null; then
        echo "Error: Cannot connect to Ollama API at localhost:11434"
        echo "Please ensure Ollama is running"
        exit 1
    fi

    echo "✓ Ollama detected and running"
    echo "Available models:"
    ollama list | head -5
}

# Install Docker
install_docker() {
    echo "Checking Docker installation..."
    
    if ! command -v docker &> /dev/null; then
        echo "Installing Docker..."
        if [ "$OS" = "Linux" ]; then
            # Install Docker on Linux
            curl -fsSL https://get.docker.com -o get-docker.sh
            sudo sh get-docker.sh
            sudo usermod -aG docker $USER
            echo "Docker installed. You may need to log out and back in for group permissions."
        elif [ "$OS" = "macOS" ]; then
            echo "Please install Docker Desktop for Mac from https://docker.com/products/docker-desktop/"
            echo "Then run this script again."
            exit 1
        fi
    else
        echo "✓ Docker already installed"
    fi
    
    # Determine Docker command
    if groups $USER | grep -q docker 2>/dev/null; then
        DOCKER_CMD="docker"
    else
        echo "Using sudo for Docker commands (user not in docker group)"
        DOCKER_CMD="sudo docker"
    fi
    
    # Test Docker
    if ! $DOCKER_CMD ps > /dev/null 2>&1; then
        echo "Error: Docker is not running or accessible"
        if [ "$OS" = "macOS" ]; then
            echo "Please start Docker Desktop"
            echo "You can find it in your Applications folder or system tray"
        else
            echo "Please start Docker service: sudo systemctl start docker"
        fi
        exit 1
    fi
    
    echo "✓ Docker is running and accessible"
}

# Check system resources
check_resources() {
    if [ "$OS" = "Linux" ]; then
        AVAILABLE_SPACE=$(df / | tail -1 | awk '{print $4}')
    elif [ "$OS" = "macOS" ]; then
        AVAILABLE_SPACE=$(df / | tail -1 | awk '{print $4}')
    fi
    
    AVAILABLE_GB=$((AVAILABLE_SPACE / 1024 / 1024))

    echo "Available disk space: ${AVAILABLE_GB}GB"

    if [ $AVAILABLE_GB -lt 5 ]; then
        echo "Warning: Low disk space (${AVAILABLE_GB}GB available)"
        echo "Open WebUI Docker image requires ~2GB"
        read -p "Continue? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

# Get network IP for external access
get_network_info() {
    if [ "$OS" = "Linux" ]; then
        LOCAL_IP=$(hostname -I | awk '{print $1}' 2>/dev/null || echo "localhost")
    elif [ "$OS" = "macOS" ]; then
        LOCAL_IP=$(ifconfig | grep "inet " | grep -v "127.0.0.1" | head -1 | awk '{print $2}' 2>/dev/null || echo "localhost")
    fi
    
    echo "Network IP detected: $LOCAL_IP"
}

# Install Open WebUI
install_openwebui() {
    echo "=========================================="
    echo "Installing Open WebUI..."
    echo "=========================================="

    # Stop existing container if running
    if $DOCKER_CMD ps -a | grep -q open-webui; then
        echo "Stopping existing Open WebUI container..."
        $DOCKER_CMD stop open-webui || true
        $DOCKER_CMD rm open-webui || true
    fi

    # Installation method selection
    echo "Select installation method:"
    echo "1. Standard setup (recommended)"
    echo "2. Network host mode (Linux only, best connectivity)"
    echo "3. Custom port configuration"
    read -p "Choose option (1-3): " -n 1 -r
    echo

    local web_port="3000"
    local web_url="http://localhost:3000"
    
    case $REPLY in
        1)
            echo "Installing Open WebUI with standard configuration..."
            if [ "$OS" = "Linux" ]; then
                $DOCKER_CMD run -d \
                    -p 3000:8080 \
                    --add-host=host.docker.internal:host-gateway \
                    -v open-webui:/app/backend/data \
                    --name open-webui \
                    --restart always \
                    ghcr.io/open-webui/open-webui:main
            else
                # macOS
                $DOCKER_CMD run -d \
                    -p 3000:8080 \
                    -v open-webui:/app/backend/data \
                    -e OLLAMA_BASE_URL=http://host.docker.internal:11434 \
                    --name open-webui \
                    --restart always \
                    ghcr.io/open-webui/open-webui:main
            fi
            ;;
        2)
            if [ "$OS" = "Linux" ]; then
                echo "Installing Open WebUI with network host mode..."
                $DOCKER_CMD run -d \
                    --network=host \
                    -v open-webui:/app/backend/data \
                    -e OLLAMA_BASE_URL=http://127.0.0.1:11434 \
                    --name open-webui \
                    --restart always \
                    ghcr.io/open-webui/open-webui:main
                web_port="8080"
                web_url="http://localhost:8080"
            else
                echo "Network host mode not supported on macOS. Using standard setup..."
                $DOCKER_CMD run -d \
                    -p 3000:8080 \
                    -v open-webui:/app/backend/data \
                    -e OLLAMA_BASE_URL=http://host.docker.internal:11434 \
                    --name open-webui \
                    --restart always \
                    ghcr.io/open-webui/open-webui:main
            fi
            ;;
        3)
            read -p "Enter port number for web interface (default 3000): " custom_port
            web_port=${custom_port:-3000}
            web_url="http://localhost:$web_port"
            
            echo "Installing Open WebUI on port $web_port..."
            if [ "$OS" = "Linux" ]; then
                $DOCKER_CMD run -d \
                    -p $web_port:8080 \
                    --add-host=host.docker.internal:host-gateway \
                    -v open-webui:/app/backend/data \
                    --name open-webui \
                    --restart always \
                    ghcr.io/open-webui/open-webui:main
            else
                $DOCKER_CMD run -d \
                    -p $web_port:8080 \
                    -v open-webui:/app/backend/data \
                    -e OLLAMA_BASE_URL=http://host.docker.internal:11434 \
                    --name open-webui \
                    --restart always \
                    ghcr.io/open-webui/open-webui:main
            fi
            ;;
        *)
            echo "Invalid option. Using standard setup..."
            if [ "$OS" = "Linux" ]; then
                $DOCKER_CMD run -d \
                    -p 3000:8080 \
                    --add-host=host.docker.internal:host-gateway \
                    -v open-webui:/app/backend/data \
                    --name open-webui \
                    --restart always \
                    ghcr.io/open-webui/open-webui:main
            else
                $DOCKER_CMD run -d \
                    -p 3000:8080 \
                    -v open-webui:/app/backend/data \
                    -e OLLAMA_BASE_URL=http://host.docker.internal:11434 \
                    --name open-webui \
                    --restart always \
                    ghcr.io/open-webui/open-webui:main
            fi
            ;;
    esac

    # Wait for container to start
    echo "Waiting for Open WebUI to start..."
    sleep 15

    # Check if container is running
    if ! $DOCKER_CMD ps | grep -q open-webui; then
        echo "Error: Open WebUI container failed to start"
        echo "Checking logs..."
        $DOCKER_CMD logs open-webui
        exit 1
    fi

    # Test web interface
    local max_attempts=6
    local attempt=1
    while [ $attempt -le $max_attempts ]; do
        if curl -s $web_url > /dev/null; then
            echo "✓ Web interface is accessible"
            break
        else
            echo "Waiting for web interface... (attempt $attempt/$max_attempts)"
            sleep 5
            ((attempt++))
        fi
    done

    echo "=========================================="
    echo "Installation Complete!"
    echo "=========================================="
    
    echo "Access URLs:"
    echo "  Local: $web_url"
    if [ "$LOCAL_IP" != "localhost" ]; then
        echo "  Network: http://$LOCAL_IP:$web_port"
    fi
    
    # Create comprehensive management script
    create_management_scripts "$web_url" "$web_port"
    
    echo ""
    echo "First-time setup:"
    echo "1. Open $web_url in your browser"
    echo "2. Create an admin account (first user becomes admin)"
    echo "3. The interface should automatically detect your Ollama models"
    echo ""
    echo "If models don't appear, check Settings > General > Ollama Server URL"
    if [ "$OS" = "Linux" ]; then
        echo "Should be set to: http://host.docker.internal:11434"
    else
        echo "Should be set to: http://host.docker.internal:11434"
    fi
}

# Create management and troubleshooting scripts
create_management_scripts() {
    local web_url="$1"
    local web_port="$2"
    
    # Main management script
    cat > ~/openwebui-manager.sh << EOF
#!/bin/bash
# Open WebUI Management Script

DOCKER_CMD="$DOCKER_CMD"
WEB_URL="$web_url"
WEB_PORT="$web_port"
LOCAL_IP="$LOCAL_IP"

show_usage() {
    echo "Usage: \$0 [start|stop|restart|status|logs|update|models|open|troubleshoot]"
    echo ""
    echo "  start        - Start Open WebUI container"
    echo "  stop         - Stop Open WebUI container"
    echo "  restart      - Restart Open WebUI container"
    echo "  status       - Show container status"
    echo "  logs         - Show container logs (use -f for follow)"
    echo "  update       - Update to latest version"
    echo "  models       - List available Ollama models"
    echo "  open         - Open web interface in browser"
    echo "  troubleshoot - Run diagnostics"
}

case \$1 in
    start)
        echo "Starting Open WebUI..."
        \$DOCKER_CMD start open-webui
        echo "Open WebUI started at \$WEB_URL"
        ;;
    stop)
        echo "Stopping Open WebUI..."
        \$DOCKER_CMD stop open-webui
        ;;
    restart)
        echo "Restarting Open WebUI..."
        \$DOCKER_CMD restart open-webui
        echo "Open WebUI restarted at \$WEB_URL"
        ;;
    status)
        echo "Container Status:"
        \$DOCKER_CMD ps -f name=open-webui
        echo ""
        echo "Service Status:"
        if curl -s \$WEB_URL > /dev/null; then
            echo "✓ Web interface accessible"
        else
            echo "✗ Web interface not accessible"
        fi
        ;;
    logs)
        if [ "\$2" = "-f" ]; then
            \$DOCKER_CMD logs -f open-webui
        else
            \$DOCKER_CMD logs --tail=50 open-webui
        fi
        ;;
    update)
        echo "Updating Open WebUI..."
        \$DOCKER_CMD pull ghcr.io/open-webui/open-webui:main
        \$DOCKER_CMD stop open-webui
        \$DOCKER_CMD rm open-webui
        echo "Container removed. Please run the installation script again to recreate with new image."
        ;;
    models)
        echo "Available Ollama models:"
        if command -v ollama &> /dev/null; then
            ollama list
        else
            echo "Ollama command not found"
        fi
        ;;
    open)
        echo "Opening \$WEB_URL in browser..."
        if command -v open &> /dev/null; then
            open \$WEB_URL &
        elif command -v xdg-open &> /dev/null; then
            xdg-open \$WEB_URL &
        else
            echo "Please open \$WEB_URL in your browser"
        fi
        ;;
    troubleshoot)
        if [ -f ~/openwebui-troubleshoot.sh ]; then
            bash ~/openwebui-troubleshoot.sh
        else
            echo "Troubleshooting script not found"
        fi
        ;;
    *)
        show_usage
        ;;
esac
EOF

    chmod +x ~/openwebui-manager.sh

    # Troubleshooting script
    cat > ~/openwebui-troubleshoot.sh << EOF
#!/bin/bash
# Open WebUI Troubleshooting Script

DOCKER_CMD="$DOCKER_CMD"
WEB_URL="$web_url"

echo "=========================================="
echo "Open WebUI Troubleshooting"
echo "=========================================="

echo "1. Checking Ollama..."
if curl -s http://localhost:11434/api/tags > /dev/null; then
    echo "✓ Ollama API accessible"
    echo "Available models:"
    curl -s http://localhost:11434/api/tags | grep -o '"name":"[^"]*"' | cut -d'"' -f4 | head -5
else
    echo "✗ Ollama API not accessible"
    echo "Try: ollama serve"
fi

echo ""
echo "2. Checking Docker container..."
if \$DOCKER_CMD ps | grep -q open-webui; then
    echo "✓ Container running"
    echo "Container info:"
    \$DOCKER_CMD inspect open-webui --format='Network: {{.HostConfig.NetworkMode}}, Ports: {{.HostConfig.PortBindings}}'
else
    echo "✗ Container not running"
    echo "Try: \$DOCKER_CMD start open-webui"
fi

echo ""
echo "3. Checking web connectivity..."
if curl -s \$WEB_URL > /dev/null; then
    echo "✓ Web interface accessible at \$WEB_URL"
else
    echo "✗ Web interface not accessible"
    echo "Checking container logs..."
    \$DOCKER_CMD logs --tail=10 open-webui
fi

echo ""
echo "4. Network connectivity test..."
echo "Testing container to Ollama connection..."
if \$DOCKER_CMD exec open-webui curl -s http://host.docker.internal:11434/api/tags > /dev/null 2>&1; then
    echo "✓ Container can reach Ollama via host.docker.internal"
elif \$DOCKER_CMD exec open-webui curl -s http://docker.for.mac.localhost:11434/api/tags > /dev/null 2>&1; then
    echo "✓ Container can reach Ollama via docker.for.mac.localhost (macOS)"
elif \$DOCKER_CMD exec open-webui curl -s http://172.17.0.1:11434/api/tags > /dev/null 2>&1; then
    echo "✓ Container can reach Ollama via Docker gateway"
else
    echo "✗ Container cannot reach Ollama"
    echo "Try recreating container or check Ollama Server URL in WebUI settings"
fi

echo ""
echo "Quick fixes:"
echo "1. Restart both services:"
echo "   \$DOCKER_CMD restart open-webui"
echo "   ollama serve"
echo ""
echo "2. Check WebUI Settings > General:"
if [ "$OS" = "Linux" ]; then
    echo "   Ollama Server URL should be http://host.docker.internal:11434"
else
    echo "   Ollama Server URL should be http://host.docker.internal:11434"
fi
echo ""
echo "3. For persistent issues on Linux, try network host mode:"
echo "   \$DOCKER_CMD stop open-webui && \$DOCKER_CMD rm open-webui"
echo "   \$DOCKER_CMD run -d --network=host -v open-webui:/app/backend/data -e OLLAMA_BASE_URL=http://127.0.0.1:11434 --name open-webui --restart always ghcr.io/open-webui/open-webui:main"
EOF

    chmod +x ~/openwebui-troubleshoot.sh

    echo "Created management scripts:"
    echo "  ~/openwebui-manager.sh - Main management interface"
    echo "  ~/openwebui-troubleshoot.sh - Diagnostic tool"
}

# Main installation function
main() {
    get_network_info
    check_ollama
    check_resources
    install_docker
    install_openwebui
    
    echo ""
    echo "Installation complete! Use the following commands:"
    echo "  ~/openwebui-manager.sh status"
    echo "  ~/openwebui-manager.sh open"
    echo "  ~/openwebui-manager.sh troubleshoot"
}

# Run installation
main "$@"
