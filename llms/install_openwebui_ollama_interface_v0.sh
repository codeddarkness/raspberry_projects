#!/bin/bash

# Open WebUI Installation Script for Raspberry Pi 5
# Integrates with existing Ollama installation
# Provides web-based interface for LLM interaction

set -e

echo "=========================================="
echo "Open WebUI Installation Script"
echo "For Raspberry Pi 5 with Ollama"
echo "=========================================="

# Check if running on Raspberry Pi
if ! grep -q "Raspberry Pi" /proc/device-tree/model 2>/dev/null; then
    echo "Warning: This script is designed for Raspberry Pi 5"
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Check if Ollama is installed and running
if ! command -v ollama &> /dev/null; then
    echo "Error: Ollama not found. Please run the Ollama installation script first."
    exit 1
fi

# Check if Ollama service is running
if ! systemctl is-active --quiet ollama; then
    echo "Starting Ollama service..."
    sudo systemctl start ollama
    sleep 3
fi

# Verify Ollama is responding
if ! curl -s http://localhost:11434/api/tags > /dev/null; then
    echo "Error: Cannot connect to Ollama API at localhost:11434"
    echo "Please ensure Ollama is running: sudo systemctl status ollama"
    exit 1
fi

echo "Ollama detected and running"
ollama list

# Check Docker installation
if ! command -v docker &> /dev/null; then
    echo "Installing Docker..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    sudo usermod -aG docker $USER
    echo "Docker installed. You may need to log out and back in for group permissions."
    echo "Continuing with sudo for Docker commands..."
    DOCKER_CMD="sudo docker"
else
    echo "Docker already installed"
    # Check if user is in docker group
    if groups $USER | grep -q docker; then
        DOCKER_CMD="docker"
    else
        echo "User not in docker group, using sudo"
        DOCKER_CMD="sudo docker"
    fi
fi

# Check available disk space
AVAILABLE_SPACE=$(df / | tail -1 | awk '{print $4}')
AVAILABLE_GB=$((AVAILABLE_SPACE / 1024 / 1024))

if [ $AVAILABLE_GB -lt 5 ]; then
    echo "Warning: Low disk space (${AVAILABLE_GB}GB available)"
    echo "Open WebUI Docker image requires ~2GB"
    read -p "Continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        exit 1
    fi
fi

echo "=========================================="
echo "Installing Open WebUI..."
echo "=========================================="

# Stop existing container if running
if $DOCKER_CMD ps -a | grep -q open-webui; then
    echo "Stopping existing Open WebUI container..."
    $DOCKER_CMD stop open-webui || true
    $DOCKER_CMD rm open-webui || true
fi

# Choose installation method
echo "Select installation method:"
echo "1. Standard setup (recommended)"
echo "2. Network host mode (troubleshooting)"
echo "3. Bundled with Ollama (alternative)"
read -p "Choose option (1-3): " -n 1 -r
echo

case $REPLY in
    1)
        echo "Installing Open WebUI with standard configuration..."
        $DOCKER_CMD run -d \
            -p 3000:8080 \
            --add-host=host.docker.internal:host-gateway \
            -v open-webui:/app/backend/data \
            --name open-webui \
            --restart always \
            ghcr.io/open-webui/open-webui:main
        
        WEB_URL="http://localhost:3000"
        ;;
    2)
        echo "Installing Open WebUI with network host mode..."
        $DOCKER_CMD run -d \
            --network=host \
            -v open-webui:/app/backend/data \
            -e OLLAMA_BASE_URL=http://127.0.0.1:11434 \
            --name open-webui \
            --restart always \
            ghcr.io/open-webui/open-webui:main
        
        WEB_URL="http://localhost:8080"
        ;;
    3)
        echo "Installing Open WebUI with bundled Ollama..."
        echo "Note: This will create a separate Ollama instance"
        $DOCKER_CMD run -d \
            -p 3000:8080 \
            -v ollama-bundle:/root/.ollama \
            -v open-webui:/app/backend/data \
            --name open-webui \
            --restart always \
            ghcr.io/open-webui/open-webui:ollama
        
        WEB_URL="http://localhost:3000"
        ;;
    *)
        echo "Invalid option. Using standard setup..."
        $DOCKER_CMD run -d \
            -p 3000:8080 \
            --add-host=host.docker.internal:host-gateway \
            -v open-webui:/app/backend/data \
            --name open-webui \
            --restart always \
            ghcr.io/open-webui/open-webui:main
        
        WEB_URL="http://localhost:3000"
        ;;
esac

# Wait for container to start
echo "Waiting for Open WebUI to start..."
sleep 10

# Check if container is running
if ! $DOCKER_CMD ps | grep -q open-webui; then
    echo "Error: Open WebUI container failed to start"
    echo "Checking logs..."
    $DOCKER_CMD logs open-webui
    exit 1
fi

echo "=========================================="
echo "Installation Complete!"
echo "=========================================="

echo "Open WebUI is now running at: $WEB_URL"
echo ""

# Test connectivity
if curl -s $WEB_URL > /dev/null; then
    echo "✓ Web interface is accessible"
else
    echo "! Web interface may not be ready yet. Wait a moment and try again."
fi

echo ""
echo "First-time setup:"
echo "1. Open $WEB_URL in your browser"
echo "2. Create an admin account (first user becomes admin)"
echo "3. The interface should automatically detect your Ollama models"

echo ""
echo "Available models in Ollama:"
ollama list

echo ""
echo "Management commands:"
echo "  View logs: $DOCKER_CMD logs open-webui"
echo "  Stop: $DOCKER_CMD stop open-webui"
echo "  Start: $DOCKER_CMD start open-webui"
echo "  Restart: $DOCKER_CMD restart open-webui"
echo "  Update: $DOCKER_CMD pull ghcr.io/open-webui/open-webui:main && $DOCKER_CMD restart open-webui"

# Create management script
cat > ~/manage-webui.sh << EOF
#!/bin/bash
# Open WebUI Management Script

DOCKER_CMD="$DOCKER_CMD"
WEB_URL="$WEB_URL"

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
        \$DOCKER_CMD ps -f name=open-webui
        ;;
    logs)
        \$DOCKER_CMD logs -f open-webui
        ;;
    update)
        echo "Updating Open WebUI..."
        \$DOCKER_CMD pull ghcr.io/open-webui/open-webui:main
        \$DOCKER_CMD stop open-webui
        \$DOCKER_CMD rm open-webui
        # Re-run original docker command based on setup
        echo "Please run the installation script again to recreate container"
        ;;
    models)
        echo "Available Ollama models:"
        ollama list
        ;;
    open)
        if command -v firefox &> /dev/null; then
            firefox \$WEB_URL &
        elif command -v chromium-browser &> /dev/null; then
            chromium-browser \$WEB_URL &
        else
            echo "Open \$WEB_URL in your browser"
        fi
        ;;
    *)
        echo "Usage: \$0 {start|stop|restart|status|logs|update|models|open}"
        echo ""
        echo "  start   - Start Open WebUI"
        echo "  stop    - Stop Open WebUI"
        echo "  restart - Restart Open WebUI"
        echo "  status  - Show container status"
        echo "  logs    - Show container logs"
        echo "  update  - Update to latest version"
        echo "  models  - List available Ollama models"
        echo "  open    - Open web interface in browser"
        ;;
esac
EOF

chmod +x ~/manage-webui.sh

echo ""
echo "Management script created: ~/manage-webui.sh"
echo "Usage: ~/manage-webui.sh {start|stop|restart|status|logs|update|models|open}"

# Troubleshooting info
cat > ~/webui-troubleshooting.txt << EOF
Open WebUI Troubleshooting Guide
================================

If you experience connection issues:

1. Check container status:
   $DOCKER_CMD ps -f name=open-webui

2. Check container logs:
   $DOCKER_CMD logs open-webui

3. Verify Ollama is running:
   curl http://localhost:11434/api/tags

4. Try network host mode if standard setup fails:
   $DOCKER_CMD stop open-webui
   $DOCKER_CMD rm open-webui
   $DOCKER_CMD run -d --network=host -v open-webui:/app/backend/data -e OLLAMA_BASE_URL=http://127.0.0.1:11434 --name open-webui --restart always ghcr.io/open-webui/open-webui:main
   # Then access at http://localhost:8080

5. Reset data volume if needed:
   $DOCKER_CMD volume rm open-webui

6. Check firewall settings if accessing remotely

Common Issues:
- "Server Connection Error": Try network host mode
- Slow responses: Models may be loading or Pi is under load
- Can't see models: Check Ollama connection in Settings > General

Web Interface: $WEB_URL
EOF

echo ""
echo "Troubleshooting guide saved: ~/webui-troubleshooting.txt"

if [ "$REPLY" = "2" ]; then
    echo ""
    echo "Note: You're using network host mode. Access the interface at http://localhost:8080"
fi

echo ""
echo "Setup complete! Open your browser and navigate to $WEB_URL to start using Open WebUI"
