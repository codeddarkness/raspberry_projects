#!/bin/bash

# source : https://github.com/open-webui/open-webui
# Open WebUI Installation Script for Raspberry Pi 5
# Integrates with existing Ollama installation
# Provides web-based interface for LLM interaction with local network access

set -e

echo "=========================================="
echo "Open WebUI Installation Script"
echo "For Raspberry Pi 5 with Ollama"
echo "Local Network Access Enabled"
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

# Get Pi's IP address
PI_IP=$(hostname -I | awk '{print $1}')
echo "Raspberry Pi IP address: $PI_IP"

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
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

echo "=========================================="
echo "Installing Open WebUI with Network Access..."
echo "=========================================="

# Stop existing container if running
if $DOCKER_CMD ps -a | grep -q open-webui; then
    echo "Stopping existing Open WebUI container..."
    $DOCKER_CMD stop open-webui || true
    $DOCKER_CMD rm open-webui || true
fi

# Choose installation method
echo "Select installation method:"
echo "1. Standard setup with network access (recommended)"
echo "2. Network host mode with full access"
echo "3. Bundled with Ollama and network access"
read -p "Choose option (1-3): " -n 1 -r
echo

case $REPLY in
    1)
        echo "Installing Open WebUI with standard configuration and network access..."
        $DOCKER_CMD run -d \
            -p 0.0.0.0:3000:8080 \
            --add-host=host.docker.internal:host-gateway \
            -v open-webui:/app/backend/data \
            --name open-webui \
            --restart always \
            ghcr.io/open-webui/open-webui:main
        
        LOCAL_URL="http://localhost:3000"
        NETWORK_URL="http://$PI_IP:3000"
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
        
        LOCAL_URL="http://localhost:8080"
        NETWORK_URL="http://$PI_IP:8080"
        ;;
    3)
        echo "Installing Open WebUI with bundled Ollama and network access..."
        echo "Note: This will create a separate Ollama instance"
        $DOCKER_CMD run -d \
            -p 0.0.0.0:3000:8080 \
            -v ollama-bundle:/root/.ollama \
            -v open-webui:/app/backend/data \
            --name open-webui \
            --restart always \
            ghcr.io/open-webui/open-webui:ollama
        
        LOCAL_URL="http://localhost:3000"
        NETWORK_URL="http://$PI_IP:3000"
        ;;
    *)
        echo "Invalid option. Using standard setup with network access..."
        $DOCKER_CMD run -d \
            -p 0.0.0.0:3000:8080 \
            --add-host=host.docker.internal:host-gateway \
            -v open-webui:/app/backend/data \
            --name open-webui \
            --restart always \
            ghcr.io/open-webui/open-webui:main
        
        LOCAL_URL="http://localhost:3000"
        NETWORK_URL="http://$PI_IP:3000"
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

# Check firewall status and provide guidance
echo "=========================================="
echo "Network Access Configuration"
echo "=========================================="

if command -v ufw &> /dev/null; then
    UFW_STATUS=$(sudo ufw status | head -1)
    echo "UFW Firewall Status: $UFW_STATUS"
    
    if echo "$UFW_STATUS" | grep -q "active"; then
        echo "Firewall is active. Opening port for Open WebUI..."
        if [[ "$LOCAL_URL" == *":3000"* ]]; then
            sudo ufw allow 3000
            echo "Port 3000 opened in firewall"
        else
            sudo ufw allow 8080
            echo "Port 8080 opened in firewall"
        fi
    fi
fi

echo "=========================================="
echo "Installation Complete!"
echo "=========================================="

echo "Open WebUI is now running and accessible:"
echo "  Local access:   $LOCAL_URL"
echo "  Network access: $NETWORK_URL"
echo ""

# Test connectivity
if curl -s $LOCAL_URL > /dev/null; then
    echo "✓ Local web interface is accessible"
else
    echo "! Web interface may not be ready yet. Wait a moment and try again."
fi

echo ""
echo "Network Access Information:"
echo "  - Other devices on your network can access: $NETWORK_URL"
echo "  - Make sure devices are on the same network as the Pi"
echo "  - Router firewall may need configuration for external access"

echo ""
echo "First-time setup:"
echo "1. Open $NETWORK_URL in your browser (from any device on the network)"
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

# Create management script
cat > ~/manage-webui.sh << EOF
#!/bin/bash
# Open WebUI Management Script

DOCKER_CMD="$DOCKER_CMD"
LOCAL_URL="$LOCAL_URL"
NETWORK_URL="$NETWORK_URL"
PI_IP="$PI_IP"

case \$1 in
    start)
        echo "Starting Open WebUI..."
        \$DOCKER_CMD start open-webui
        echo "Open WebUI started"
        echo "  Local:   \$LOCAL_URL"
        echo "  Network: \$NETWORK_URL"
        ;;
    stop)
        echo "Stopping Open WebUI..."
        \$DOCKER_CMD stop open-webui
        ;;
    restart)
        echo "Restarting Open WebUI..."
        \$DOCKER_CMD restart open-webui
        echo "Open WebUI restarted"
        echo "  Local:   \$LOCAL_URL"
        echo "  Network: \$NETWORK_URL"
        ;;
    status)
        \$DOCKER_CMD ps -f name=open-webui
        echo ""
        echo "Access URLs:"
        echo "  Local:   \$LOCAL_URL"
        echo "  Network: \$NETWORK_URL"
        ;;
    logs)
        \$DOCKER_CMD logs -f open-webui
        ;;
    ip)
        CURRENT_IP=\$(hostname -I | awk '{print \$1}')
        echo "Current Pi IP: \$CURRENT_IP"
        echo "Network URL: http://\$CURRENT_IP:${NETWORK_URL##*:}"
        ;;
    models)
        echo "Available Ollama models:"
        ollama list
        ;;
    open)
        if command -v firefox &> /dev/null; then
            firefox \$LOCAL_URL &
        elif command -v chromium-browser &> /dev/null; then
            chromium-browser \$LOCAL_URL &
        else
            echo "Open \$LOCAL_URL in your browser"
        fi
        ;;
    firewall)
        if command -v ufw &> /dev/null; then
            echo "UFW Status:"
            sudo ufw status
            echo ""
            echo "To allow network access:"
            if [[ "\$LOCAL_URL" == *":3000"* ]]; then
                echo "  sudo ufw allow 3000"
            else
                echo "  sudo ufw allow 8080"
            fi
        else
            echo "UFW firewall not installed"
        fi
        ;;
    *)
        echo "Usage: \$0 {start|stop|restart|status|logs|ip|models|open|firewall}"
        echo ""
        echo "  start    - Start Open WebUI"
        echo "  stop     - Stop Open WebUI"
        echo "  restart  - Restart Open WebUI"
        echo "  status   - Show container status and URLs"
        echo "  logs     - Show container logs"
        echo "  ip       - Show current IP and network URL"
        echo "  models   - List available Ollama models"
        echo "  open     - Open web interface in local browser"
        echo "  firewall - Check/configure firewall settings"
        echo ""
        echo "Access URLs:"
        echo "  Local:   \$LOCAL_URL"
        echo "  Network: \$NETWORK_URL"
        ;;
esac
EOF

chmod +x ~/manage-webui.sh

echo ""
echo "Management script created: ~/manage-webui.sh"
echo "Usage: ~/manage-webui.sh {start|stop|restart|status|logs|ip|models|open|firewall}"

# Create network access guide
cat > ~/network-access-guide.txt << EOF
Open WebUI Network Access Guide
===============================

Your Open WebUI is accessible at:
  Local (Pi only):     $LOCAL_URL  
  Network (all devices): $NETWORK_URL

Network Access Checklist:
□ Container is running: docker ps | grep open-webui
□ Port is accessible: netstat -ln | grep :${NETWORK_URL##*:}
□ Firewall allows access: sudo ufw status
□ Devices on same network as Pi ($PI_IP)

Troubleshooting Network Access:
1. Test from Pi: curl $LOCAL_URL
2. Check container: docker logs open-webui
3. Check port binding: docker port open-webui
4. Test from other device: ping $PI_IP

Security Notes:
- First user becomes admin
- Consider setting strong passwords
- Monitor access logs if needed
- Use HTTPS in production environments

Router Configuration (if needed):
- Port forwarding for external access
- Static IP assignment for Pi
- DMZ settings (not recommended)

Commands:
- Check IP: hostname -I
- Test connectivity: nc -zv $PI_IP ${NETWORK_URL##*:}
- Restart container: docker restart open-webui
EOF

echo ""
echo "Network access guide saved: ~/network-access-guide.txt"

echo ""
echo "Setup complete! Access Open WebUI from any device on your network:"
echo "  $NETWORK_URL"
echo ""
echo "The web interface is now accessible from other devices on your local network."
