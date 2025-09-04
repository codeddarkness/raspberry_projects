#!/bin/bash

# Universal Model Connection Troubleshooting Script
# Diagnoses and fixes connection issues between Open WebUI and Ollama
# Works on Linux and macOS

set -e

echo "=========================================="
echo "Universal Model Connection Troubleshooter"
echo "=========================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# System detection
OS="$(uname -s)"
DOCKER_CMD=""

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

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

# Detect Docker command
detect_docker() {
    if command -v docker &> /dev/null; then
        if groups $USER | grep -q docker 2>/dev/null; then
            DOCKER_CMD="docker"
        else
            DOCKER_CMD="sudo docker"
        fi
    else
        print_warning "Docker not found"
        DOCKER_CMD=""
    fi
}

# Step 1: Check Ollama service status
check_ollama_service() {
    echo "Step 1: Checking Ollama service status..."
    
    if command -v ollama &> /dev/null; then
        print_status 0 "Ollama command available"
    else
        print_status 1 "Ollama command not found"
        echo "Please install Ollama first using the installation script"
        return 1
    fi
    
    # Check if Ollama is running
    if curl -s http://localhost:11434/api/tags > /dev/null; then
        print_status 0 "Ollama API is accessible on localhost:11434"
        
        # Show available models
        echo "Available models in Ollama:"
        ollama list | head -10
        echo ""
        
        # Show model details
        MODEL_COUNT=$(ollama list | tail -n +2 | wc -l)
        if [ $MODEL_COUNT -eq 0 ]; then
            print_warning "No models installed in Ollama"
            echo "Use: ollama pull <model_name> to install models"
            echo "Popular models: gemma2:2b, qwen2.5:7b, llama3.1:8b"
        else
            print_status 0 "$MODEL_COUNT models available"
        fi
        
    else
        print_status 1 "Cannot reach Ollama API"
        echo "Attempting to start Ollama service..."
        
        if [ "$OS" = "Linux" ]; then
            if systemctl is-enabled ollama &> /dev/null; then
                sudo systemctl restart ollama
                sleep 3
            else
                print_warning "Ollama systemd service not found, starting manually"
                ollama serve > /tmp/ollama.log 2>&1 &
                sleep 5
            fi
        else
            # macOS
            print_info "Starting Ollama manually on macOS"
            ollama serve > /tmp/ollama.log 2>&1 &
            sleep 5
        fi
        
        if curl -s http://localhost:11434/api/tags > /dev/null; then
            print_status 0 "Ollama API now accessible after restart"
        else
            print_status 1 "Ollama API still not accessible"
            echo "Check Ollama installation and logs:"
            echo "  Manual start: ollama serve"
            echo "  Check logs: tail -f /tmp/ollama.log"
            return 1
        fi
    fi
}

# Step 2: Check Open WebUI container status
check_openwebui_container() {
    echo ""
    echo "Step 2: Checking Open WebUI container status..."
    
    if [ -z "$DOCKER_CMD" ]; then
        print_status 1 "Docker not available"
        return 1
    fi
    
    if $DOCKER_CMD ps | grep -q open-webui; then
        print_status 0 "Open WebUI container is running"
        
        # Get container network info
        echo "Container configuration:"
        NETWORK_MODE=$($DOCKER_CMD inspect open-webui --format='{{.HostConfig.NetworkMode}}' 2>/dev/null || echo "unknown")
        PORT_BINDINGS=$($DOCKER_CMD inspect open-webui --format='{{.HostConfig.PortBindings}}' 2>/dev/null || echo "unknown")
        
        echo "  Network mode: $NETWORK_MODE"
        echo "  Port bindings: $PORT_BINDINGS"
        
    else
        print_status 1 "Open WebUI container is not running"
        
        # Check if container exists but is stopped
        if $DOCKER_CMD ps -a | grep -q open-webui; then
            echo "Starting stopped Open WebUI container..."
            $DOCKER_CMD start open-webui
            sleep 5
        else
            print_warning "Open WebUI container does not exist"
            echo "Please run the Open WebUI installation script first"
            return 1
        fi
    fi
}

# Step 3: Test web interface connectivity
check_web_interface() {
    echo ""
    echo "Step 3: Testing web interface connectivity..."
    
    # Try different common ports
    WEB_PORTS=(3000 8080)
    WEB_URL=""
    
    for port in "${WEB_PORTS[@]}"; do
        if curl -s http://localhost:$port > /dev/null; then
            WEB_URL="http://localhost:$port"
            print_status 0 "Web interface accessible at $WEB_URL"
            break
        fi
    done
    
    if [ -z "$WEB_URL" ]; then
        print_status 1 "Web interface not accessible on standard ports"
        
        # Check what ports the container is actually using
        if [ -n "$DOCKER_CMD" ] && $DOCKER_CMD ps | grep -q open-webui; then
            echo "Container port mapping:"
            $DOCKER_CMD port open-webui
        fi
        return 1
    fi
}

# Step 4: Test connectivity from container to host
check_container_to_host() {
    echo ""
    echo "Step 4: Testing connectivity from container to host..."
    
    if [ -z "$DOCKER_CMD" ] || ! $DOCKER_CMD ps | grep -q open-webui; then
        print_warning "Skipping - Open WebUI container not running"
        return
    fi
    
    # Test different connection methods
    CONNECTION_METHODS=()
    
    if [ "$OS" = "Linux" ]; then
        CONNECTION_METHODS=("host.docker.internal:11434" "172.17.0.1:11434" "$(hostname -I | awk '{print $1}'):11434")
    else
        # macOS
        CONNECTION_METHODS=("host.docker.internal:11434" "docker.for.mac.localhost:11434")
    fi
    
    WORKING_METHOD=""
    
    for method in "${CONNECTION_METHODS[@]}"; do
        if $DOCKER_CMD exec open-webui curl -s http://$method/api/tags > /dev/null 2>&1; then
            print_status 0 "Container can reach Ollama via $method"
            WORKING_METHOD="http://$method"
            break
        fi
    done
    
    if [ -z "$WORKING_METHOD" ]; then
        print_status 1 "Container cannot reach Ollama API"
        echo ""
        echo "Attempting to fix connectivity..."
        fix_connectivity_issues
    else
        echo "Recommended Ollama Server URL for WebUI: $WORKING_METHOD"
    fi
}

# Step 5: Check and configure Ollama for external access
configure_ollama_access() {
    echo ""
    echo "Step 5: Configuring Ollama for external access..."
    
    if [ "$OS" = "Linux" ]; then
        OLLAMA_CONFIG="/etc/systemd/system/ollama.service.d/override.conf"
        
        if [ -f "$OLLAMA_CONFIG" ] && grep -q "0.0.0.0" "$OLLAMA_CONFIG"; then
            print_status 0 "Ollama configured for external connections"
        else
            print_warning "Configuring Ollama to accept connections from Docker..."
            
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
    else
        # macOS - check if Ollama is bound to all interfaces
        print_info "On macOS, ensure Ollama is accessible to Docker"
        print_info "If issues persist, restart Ollama with: ollama serve"
    fi
}

# Fix connectivity issues
fix_connectivity_issues() {
    echo "Applying connectivity fixes..."
    
    if [ "$OS" = "Linux" ]; then
        echo "Trying network host mode (Linux only)..."
        
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
        
        if curl -s http://localhost:8080 > /dev/null; then
            print_status 0 "Fixed! Open WebUI now accessible at http://localhost:8080"
        else
            print_status 1 "Still having connectivity issues"
        fi
        
    else
        # macOS - try different approach
        echo "Recreating container with updated settings..."
        
        $DOCKER_CMD stop open-webui
        $DOCKER_CMD rm open-webui
        
        $DOCKER_CMD run -d \
            -p 3000:8080 \
            -e OLLAMA_BASE_URL=http://host.docker.internal:11434 \
            -v open-webui:/app/backend/data \
            --name open-webui \
            --restart always \
            ghcr.io/open-webui/open-webui:main
        
        sleep 10
        
        if curl -s http://localhost:3000 > /dev/null; then
            print_status 0 "Fixed! Open WebUI now accessible at http://localhost:3000"
        else
            print_status 1 "Still having connectivity issues"
        fi
    fi
}

# Step 6: Final verification and model integration
final_verification() {
    echo ""
    echo "Step 6: Final verification..."
    
    # Determine current web URL
    WEB_URL=""
    for port in 8080 3000; do
        if curl -s http://localhost:$port > /dev/null; then
            WEB_URL="http://localhost:$port"
            break
        fi
    done
    
    if [ -n "$WEB_URL" ]; then
        print_status 0 "Open WebUI is accessible at $WEB_URL"
        
        # Test model availability through WebUI API
        echo "Testing model availability through WebUI..."
        
        sleep 5  # Give WebUI time to connect to Ollama
        
        MODELS_RESPONSE=$(curl -s $WEB_URL/api/models 2>/dev/null || echo "")
        
        if [ ! -z "$MODELS_RESPONSE" ] && [ "$MODELS_RESPONSE" != "[]" ]; then
            print_status 0 "Models are available in Open WebUI"
            echo "Available models via WebUI API:"
            echo "$MODELS_RESPONSE" | grep -o '"id":"[^"]*"' | cut -d'"' -f4 | head -5
        else
            print_warning "Models may not be visible in WebUI yet"
            echo "This might resolve after:"
            echo "1. Refreshing the web browser"
            echo "2. Checking WebUI Settings > General > Ollama Server URL"
        fi
    else
        print_status 1 "Open WebUI is not accessible"
    fi
}

# Create enhanced verification script
create_verification_script() {
    cat > ~/ollama-webui-verify.sh << 'EOF'
#!/bin/bash

# Ollama and Open WebUI Verification Script

echo "=== Ollama & Open WebUI Status Check ==="
echo ""

# Check Ollama
echo "1. Ollama Service:"
if curl -s http://localhost:11434/api/tags > /dev/null; then
    echo "   ✓ Ollama API accessible at http://localhost:11434"
    echo "   Available models:"
    ollama list | tail -n +2 | awk '{print "     - " $1}' | head -5
    
    MODEL_COUNT=$(ollama list | tail -n +2 | wc -l)
    echo "   Total models: $MODEL_COUNT"
else
    echo "   ✗ Ollama API not accessible"
    echo "   Try: ollama serve"
fi

echo ""
echo "2. Open WebUI Service:"

# Determine Docker command
if groups $USER | grep -q docker 2>/dev/null; then
    DOCKER_CMD="docker"
else
    DOCKER_CMD="sudo docker"
fi

WEB_URL=""
for port in 8080 3000; do
    if curl -s http://localhost:$port > /dev/null; then
        WEB_URL="http://localhost:$port"
        break
    fi
done

if [ -n "$WEB_URL" ]; then
    echo "   ✓ Open WebUI accessible at $WEB_URL"
    
    # Test model API
    if curl -s $WEB_URL/api/models > /dev/null; then
        echo "   ✓ WebUI can access models"
    else
        echo "   ! WebUI model API may not be ready"
    fi
else
    echo "   ✗ Open WebUI not accessible"
    echo "   Check: $DOCKER_CMD ps | grep open-webui"
fi

echo ""
echo "3. Container Network:"
if $DOCKER_CMD ps | grep -q open-webui; then
    NETWORK_MODE=$($DOCKER_CMD inspect open-webui --format '{{.HostConfig.NetworkMode}}' 2>/dev/null || echo "unknown")
    echo "   Container network mode: $NETWORK_MODE"
    
    # Test container to host connectivity
    if $DOCKER_CMD exec open-webui curl -s http://host.docker.internal:11434/api/tags > /dev/null 2>&1; then
        echo "   ✓ Container can reach Ollama"
        echo "   Recommended WebUI setting: http://host.docker.internal:11434"
    elif $DOCKER_CMD exec open-webui curl -s http://docker.for.mac.localhost:11434/api/tags > /dev/null 2>&1; then
        echo "   ✓ Container can reach Ollama (macOS)"
        echo "   Recommended WebUI setting: http://docker.for.mac.localhost:11434"
    else
        echo "   ✗ Container cannot reach Ollama"
    fi
else
    echo "   ✗ Container not running"
fi

echo ""
echo "Quick Actions:"
if [ -n "$WEB_URL" ]; then
    echo "   Open WebUI: $WEB_URL"
fi
echo "   Restart Ollama: ollama serve"
echo "   Restart WebUI: $DOCKER_CMD restart open-webui"
echo "   View WebUI logs: $DOCKER_CMD logs open-webui"

# Integration with model library
if [ -f ~/ollama-models/library/ollama_model_library.list ]; then
    echo ""
    echo "4. Model Library Integration:"
    echo "   ✓ Model library available"
    TOTAL_MODELS=$(wc -l < ~/ollama-models/library/ollama_model_library.list)
    echo "   Available for download: $TOTAL_MODELS models"
    echo "   Use: ~/ollama-models.sh search <term>"
else
    echo ""
    echo "4. Model Library:"
    echo "   ! Model library not found"
    echo "   Run: ~/ollama-models.sh update-library"
fi
EOF

    chmod +x ~/ollama-webui-verify.sh
    
    echo ""
    echo "Created enhanced verification script: ~/ollama-webui-verify.sh"
}

# Generate troubleshooting summary
generate_summary() {
    echo ""
    echo "=========================================="
    echo "Troubleshooting Summary"
    echo "=========================================="
    
    # Determine current configuration
    if [ -n "$DOCKER_CMD" ] && $DOCKER_CMD ps | grep -q open-webui; then
        NETWORK_MODE=$($DOCKER_CMD inspect open-webui --format '{{.HostConfig.NetworkMode}}' 2>/dev/null || echo "unknown")
        
        if [ "$NETWORK_MODE" = "host" ]; then
            echo "Configuration: Network Host Mode (Linux)"
            echo "Access URL: http://localhost:8080"
        else
            echo "Configuration: Bridge Mode"
            echo "Access URL: http://localhost:3000"
        fi
        
        if [ "$OS" = "Linux" ]; then
            LOCAL_IP=$(hostname -I | awk '{print $1}' 2>/dev/null || echo "unknown")
        else
            LOCAL_IP=$(ifconfig | grep "inet " | grep -v "127.0.0.1" | head -1 | awk '{print $2}' 2>/dev/null || echo "unknown")
        fi
        
        if [ "$LOCAL_IP" != "unknown" ]; then
            if [ "$NETWORK_MODE" = "host" ]; then
                echo "Network URL: http://$LOCAL_IP:8080"
            else
                echo "Network URL: http://$LOCAL_IP:3000"
            fi
        fi
    fi
    
    echo ""
    echo "Quick verification commands:"
    echo "  Test Ollama: curl http://localhost:11434/api/tags"
    echo "  Test WebUI: curl http://localhost:3000 (or :8080)"
    echo "  View logs: $DOCKER_CMD logs open-webui"
    echo "  List models: ollama list"
    echo "  Full check: ~/ollama-webui-verify.sh"
    
    echo ""
    echo "If models are still not visible in WebUI:"
    echo "1. Refresh the web browser (Ctrl+F5 / Cmd+F5)"
    echo "2. Check Settings > General in WebUI"
    echo "3. Verify Ollama Server URL setting:"
    if [ "$OS" = "Linux" ]; then
        echo "   - Try: http://host.docker.internal:11434"
        echo "   - Or: http://172.17.0.1:11434"
    else
        echo "   - Try: http://host.docker.internal:11434"
        echo "   - Or: http://docker.for.mac.localhost:11434"
    fi
    echo "4. Restart both services if needed"
    
    echo ""
    echo "Model management:"
    echo "  Browse models: ~/ollama-models.sh search <term>"
    echo "  Install model: ollama pull <model_name>"
    echo "  Remove model: ollama rm <model_name>"
}

# Main troubleshooting flow
main() {
    detect_docker
    
    if ! check_ollama_service; then
        echo "Cannot proceed without working Ollama installation"
        exit 1
    fi
    
    check_openwebui_container
    check_web_interface
    check_container_to_host
    configure_ollama_access
    final_verification
    create_verification_script
    generate_summary
    
    echo ""
    echo "Troubleshooting complete!"
    echo "Run ~/ollama-webui-verify.sh anytime to check status"
}

# Run main troubleshooting
main "$@"
