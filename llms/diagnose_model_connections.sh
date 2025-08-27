#!/bin/bash

# Open WebUI Model Connection Troubleshooting Script
# Diagnoses and fixes connection issues between Open WebUI and Ollama

set -e

echo "=========================================="
echo "Open WebUI Model Connection Troubleshooter"
echo "=========================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_status() {
    if [ $1 -eq 0 ]; then
        echo -e "${GREEN}✓${NC} $2"
    else
        echo -e "${RED}✗${NC} $2"
    fi
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

# Check Docker command
if groups $USER | grep -q docker; then
    DOCKER_CMD="docker"
else
    DOCKER_CMD="sudo docker"
fi

echo "Step 1: Checking Ollama service status..."
# Check if Ollama is running
if systemctl is-active --quiet ollama; then
    print_status 0 "Ollama service is running"
else
    print_status 1 "Ollama service is not running"
    echo "Starting Ollama service..."
    sudo systemctl start ollama
    sleep 3
fi

echo ""
echo "Step 2: Testing Ollama API connectivity..."
# Test Ollama API
if curl -s http://localhost:11434/api/tags > /dev/null; then
    print_status 0 "Ollama API is accessible on localhost:11434"
    
    # Show available models
    echo "Available models in Ollama:"
    ollama list
else
    print_status 1 "Cannot reach Ollama API"
    echo "Attempting to start Ollama service..."
    sudo systemctl restart ollama
    sleep 5
    
    if curl -s http://localhost:11434/api/tags > /dev/null; then
        print_status 0 "Ollama API now accessible after restart"
    else
        print_status 1 "Ollama API still not accessible"
        echo "Check Ollama installation: curl http://localhost:11434/api/tags"
        exit 1
    fi
fi

echo ""
echo "Step 3: Checking Open WebUI container status..."
# Check if Open WebUI container is running
if $DOCKER_CMD ps | grep -q open-webui; then
    print_status 0 "Open WebUI container is running"
    
    # Get container network info
    echo "Container network configuration:"
    $DOCKER_CMD inspect open-webui --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}'
else
    print_status 1 "Open WebUI container is not running"
    echo "Starting Open WebUI container..."
    $DOCKER_CMD start open-webui
    sleep 5
fi

echo ""
echo "Step 4: Testing connectivity from container to host..."
# Test if container can reach host Ollama
if $DOCKER_CMD exec open-webui curl -s http://host.docker.internal:11434/api/tags > /dev/null 2>&1; then
    print_status 0 "Container can reach Ollama via host.docker.internal"
elif $DOCKER_CMD exec open-webui curl -s http://172.17.0.1:11434/api/tags > /dev/null 2>&1; then
    print_status 0 "Container can reach Ollama via Docker gateway"
    print_warning "Consider updating OLLAMA_BASE_URL to http://172.17.0.1:11434"
else
    print_status 1 "Container cannot reach Ollama API"
    echo ""
    echo "Fixing connectivity issue..."
    
    # Get host IP
    HOST_IP=$(hostname -I | awk '{print $1}')
    
    echo "Trying different connection methods..."
    
    # Method 1: Recreate with network host
    echo "Attempting fix: Using network host mode"
    $DOCKER_CMD stop open-webui
    $DOCKER_CMD rm open-webui
    
    $DOCKER_CMD run -d \
        --network=host \
        -v open-webui:/app/backend/data \
        -e OLLAMA_BASE_URL=http://127.0.0.1:11434 \
        --name open-webui \
        --restart always \
        ghcr.io/open-webui/open-webui:main
    
    sleep 10
    
    # Test the fix
    if curl -s http://localhost:8080 > /dev/null; then
        print_status 0 "Fixed! Open WebUI now accessible at http://localhost:8080"
        
        # Update the management script
        sed -i 's|LOCAL_URL="http://localhost:3000"|LOCAL_URL="http://localhost:8080"|g' ~/manage-webui.sh 2>/dev/null || true
        sed -i 's|NETWORK_URL="http://.*:3000"|NETWORK_URL="http://'$HOST_IP':8080"|g' ~/manage-webui.sh 2>/dev/null || true
        
        echo "Updated access URLs:"
        echo "  Local: http://localhost:8080"
        echo "  Network: http://$HOST_IP:8080"
    else
        print_status 1 "Still having connectivity issues"
    fi
fi

echo ""
echo "Step 5: Checking Ollama configuration..."
# Check if Ollama is configured to accept external connections
OLLAMA_CONFIG="/etc/systemd/system/ollama.service.d/override.conf"

if [ -f "$OLLAMA_CONFIG" ] && grep -q "0.0.0.0" "$OLLAMA_CONFIG"; then
    print_status 0 "Ollama configured for external connections"
else
    print_warning "Ollama may not be configured for external connections"
    echo "Configuring Ollama to accept connections from Docker..."
    
    sudo mkdir -p /etc/systemd/system/ollama.service.d/
    sudo tee $OLLAMA_CONFIG > /dev/null <<EOF
[Service]
Environment="OLLAMA_HOST=0.0.0.0"
EOF
    
    sudo systemctl daemon-reload
    sudo systemctl restart ollama
    sleep 5
    
    print_status 0 "Ollama configured and restarted"
fi

echo ""
echo "Step 6: Final verification..."
# Final test
sleep 5

if curl -s http://localhost:8080 > /dev/null || curl -s http://localhost:3000 > /dev/null; then
    print_status 0 "Open WebUI is accessible"
    
    # Try to get models via the WebUI API
    if curl -s http://localhost:8080/api/models > /dev/null 2>&1; then
        WEB_URL="http://localhost:8080"
    elif curl -s http://localhost:3000/api/models > /dev/null 2>&1; then
        WEB_URL="http://localhost:3000"
    fi
    
    echo ""
    echo "Testing model availability through WebUI..."
    MODELS_RESPONSE=$(curl -s $WEB_URL/api/models 2>/dev/null || echo "")
    
    if [ ! -z "$MODELS_RESPONSE" ] && [ "$MODELS_RESPONSE" != "[]" ]; then
        print_status 0 "Models are now available in Open WebUI"
    else
        print_warning "Models may still not be visible in WebUI"
        echo "Try refreshing the web interface or check WebUI settings"
    fi
else
    print_status 1 "Open WebUI is not accessible"
fi

echo ""
echo "=========================================="
echo "Troubleshooting Summary"
echo "=========================================="

# Determine current configuration
if $DOCKER_CMD inspect open-webui --format '{{.HostConfig.NetworkMode}}' 2>/dev/null | grep -q host; then
    echo "Configuration: Network Host Mode"
    echo "Access URL: http://localhost:8080"
    echo "Network URL: http://$(hostname -I | awk '{print $1}'):8080"
else
    echo "Configuration: Bridge Mode"
    echo "Access URL: http://localhost:3000"
    echo "Network URL: http://$(hostname -I | awk '{print $1}'):3000"
fi

echo ""
echo "Quick verification commands:"
echo "  Test Ollama: curl http://localhost:11434/api/tags"
echo "  Test WebUI: curl http://localhost:8080 (or :3000)"
echo "  View logs: $DOCKER_CMD logs open-webui"
echo "  List models: ollama list"

echo ""
echo "If models are still not visible:"
echo "1. Refresh the web browser"
echo "2. Check Settings > General in WebUI"
echo "3. Verify Ollama Server URL setting"
echo "4. Try manually setting: http://localhost:11434"

# Create a verification script
cat > ~/verify-models.sh << 'EOF'
#!/bin/bash

echo "=== Model Availability Verification ==="
echo ""

echo "1. Ollama API Status:"
if curl -s http://localhost:11434/api/tags > /dev/null; then
    echo "   ✓ Ollama API accessible"
    echo "   Available models:"
    ollama list | grep -v "NAME" | awk '{print "     - " $1}'
else
    echo "   ✗ Ollama API not accessible"
fi

echo ""
echo "2. Open WebUI Status:"
if curl -s http://localhost:8080 > /dev/null; then
    echo "   ✓ Open WebUI accessible at http://localhost:8080"
elif curl -s http://localhost:3000 > /dev/null; then
    echo "   ✓ Open WebUI accessible at http://localhost:3000"
else
    echo "   ✗ Open WebUI not accessible"
fi

echo ""
echo "3. Container Network:"
if docker ps | grep -q open-webui; then
    NETWORK_MODE=$(docker inspect open-webui --format '{{.HostConfig.NetworkMode}}' 2>/dev/null)
    echo "   Network mode: $NETWORK_MODE"
    
    if [ "$NETWORK_MODE" = "host" ]; then
        echo "   Using host networking - should work with localhost:11434"
    else
        echo "   Using bridge networking - may need host.docker.internal:11434"
    fi
else
    echo "   ✗ Container not running"
fi

echo ""
echo "If models aren't showing, try:"
echo "1. Refresh browser (Ctrl+F5)"
echo "2. Check WebUI Settings > General > Ollama Server URL"
echo "3. Set Ollama URL manually to: http://localhost:11434"
EOF

chmod +x ~/verify-models.sh

echo ""
echo "Created verification script: ~/verify-models.sh"
echo "Run it anytime to check model availability"

echo ""
echo "Troubleshooting complete. Try accessing Open WebUI now."
