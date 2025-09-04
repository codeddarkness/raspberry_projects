cat << 'EOF' > ~/create_missing_scripts.sh
#!/bin/bash

echo "Creating missing LLM management scripts..."

# Create ollama-launcher.sh
cat << 'LAUNCHER_EOF' > ~/ollama-launcher.sh
#!/bin/bash

# Ollama Launcher Script
# Choose between CPU and GPU modes

show_usage() {
    echo "Usage: $0 [cpu|gpu|auto|status|models|install]"
    echo "  cpu     - Start with CPU only"
    echo "  gpu     - Start with GPU acceleration"
    echo "  auto    - Auto-detect best option"
    echo "  status  - Show current status"
    echo "  models  - List available models"
    echo "  install - Interactive model installer"
}

start_cpu() {
    echo "Starting Ollama in CPU mode..."
    export OLLAMA_NUM_GPU=0
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        if systemctl is-enabled ollama &> /dev/null; then
            sudo systemctl restart ollama
        else
            ollama serve > /tmp/ollama.log 2>&1 &
        fi
    else
        # macOS
        if command -v brew &> /dev/null && brew services list | grep -q ollama; then
            brew services restart ollama
        else
            ollama serve > /tmp/ollama.log 2>&1 &
        fi
    fi
}

start_gpu() {
    echo "Starting Ollama with GPU acceleration..."
    unset OLLAMA_NUM_GPU
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        if systemctl is-enabled ollama &> /dev/null; then
            sudo systemctl restart ollama
        else
            ollama serve > /tmp/ollama.log 2>&1 &
        fi
    else
        # macOS
        if command -v brew &> /dev/null && brew services list | grep -q ollama; then
            brew services restart ollama
        else
            ollama serve > /tmp/ollama.log 2>&1 &
        fi
    fi
}

show_status() {
    echo "Ollama Status:"
    if curl -s http://localhost:11434/api/tags > /dev/null; then
        echo "✓ Ollama is running"
        echo "Available models:"
        ollama list
    else
        echo "✗ Ollama is not running"
        echo "Try: brew services start ollama"
        echo "Or: ollama serve"
    fi
}

install_models() {
    if [ -f ~/ollama-models/library/ollama_model_library.list ]; then
        echo "Available models (first 20):"
        head -20 ~/ollama-models/library/ollama_model_library.list
        echo ""
        read -p "Enter model name to install: " model_name
        if [ ! -z "$model_name" ]; then
            ollama pull "$model_name"
        fi
    else
        echo "Model library not available. Popular models:"
        echo "llama3.1:8b, qwen2.5:7b, mistral:7b, gemma2:9b, codellama:7b"
        read -p "Enter model name to install: " model_name
        if [ ! -z "$model_name" ]; then
            ollama pull "$model_name"
        fi
    fi
}

case $1 in
    cpu)
        start_cpu
        ;;
    gpu)
        start_gpu
        ;;
    auto)
        # Auto-detect GPU support and start accordingly
        if command -v nvidia-smi &> /dev/null && nvidia-smi > /dev/null 2>&1; then
            start_gpu
        elif command -v rocm-smi &> /dev/null && rocm-smi > /dev/null 2>&1; then
            start_gpu
        elif [[ "$OSTYPE" == "darwin"* ]]; then
            start_gpu  # macOS has Metal support
        else
            start_cpu
        fi
        ;;
    status)
        show_status
        ;;
    models)
        ollama list
        ;;
    install)
        install_models
        ;;
    *)
        show_usage
        ;;
esac
LAUNCHER_EOF

# Create ollama-models.sh
cat << 'MODELS_EOF' > ~/ollama-models.sh
#!/bin/bash

# Ollama Model Management Script

show_usage() {
    echo "Usage: $0 [list|search|install|remove|update-library]"
    echo "  list           - List installed models"
    echo "  search <term>  - Search available models"
    echo "  install <model> - Install a model"
    echo "  remove <model>  - Remove a model"
    echo "  update-library - Update model library from ollama.com"
}

update_library() {
    echo "Updating model library..."
    cd ~/ollama-models/library 2>/dev/null || {
        mkdir -p ~/ollama-models/library
        cd ~/ollama-models/library
    }
    
    if [ -f get_model_list.sh ]; then
        rm -f ollama_model_library.*
        ./get_model_list.sh
        echo "Library updated!"
    else
        echo "Library update script not found. Please run the installation script first."
        exit 1
    fi
}

search_models() {
    if [ -f ~/ollama-models/library/ollama_model_library.list ]; then
        echo "Searching for: $1"
        grep -i "$1" ~/ollama-models/library/ollama_model_library.list || echo "No matches found"
    else
        echo "Model library not available. Run: $0 update-library"
    fi
}

case $1 in
    list)
        ollama list
        ;;
    search)
        if [ -z "$2" ]; then
            echo "Please provide a search term"
        else
            search_models "$2"
        fi
        ;;
    install)
        if [ -z "$2" ]; then
            echo "Please provide a model name"
        else
            ollama pull "$2"
        fi
        ;;
    remove)
        if [ -z "$2" ]; then
            echo "Please provide a model name"
        else
            ollama rm "$2"
        fi
        ;;
    update-library)
        update_library
        ;;
    *)
        show_usage
        ;;
esac
MODELS_EOF

# Create openwebui-manager.sh
cat << 'WEBUI_EOF' > ~/openwebui-manager.sh
#!/bin/bash
# Open WebUI Management Script

DOCKER_CMD="sudo docker"
WEB_URL="http://localhost:3000"
WEB_PORT="3000"
LOCAL_IP="10.0.0.70"

show_usage() {
    echo "Usage: $0 [start|stop|restart|status|logs|update|models|open|troubleshoot]"
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

case $1 in
    start)
        echo "Starting Open WebUI..."
        $DOCKER_CMD start open-webui
        echo "Open WebUI started at $WEB_URL"
        ;;
    stop)
        echo "Stopping Open WebUI..."
        $DOCKER_CMD stop open-webui
        ;;
    restart)
        echo "Restarting Open WebUI..."
        $DOCKER_CMD restart open-webui
        echo "Open WebUI restarted at $WEB_URL"
        ;;
    status)
        echo "Container Status:"
        $DOCKER_CMD ps -f name=open-webui
        echo ""
        echo "Service Status:"
        if curl -s $WEB_URL > /dev/null; then
            echo "✓ Web interface accessible"
        else
            echo "✗ Web interface not accessible"
        fi
        ;;
    logs)
        if [ "$2" = "-f" ]; then
            $DOCKER_CMD logs -f open-webui
        else
            $DOCKER_CMD logs --tail=50 open-webui
        fi
        ;;
    update)
        echo "Updating Open WebUI..."
        $DOCKER_CMD pull ghcr.io/open-webui/open-webui:main
        $DOCKER_CMD stop open-webui
        $DOCKER_CMD rm open-webui
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
        echo "Opening $WEB_URL in browser..."
        if command -v open &> /dev/null; then
            open $WEB_URL &
        elif command -v xdg-open &> /dev/null; then
            xdg-open $WEB_URL &
        else
            echo "Please open $WEB_URL in your browser"
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
WEBUI_EOF

# Create ollama-webui-verify.sh
cat << 'VERIFY_EOF' > ~/ollama-webui-verify.sh
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
    echo "   Try: brew services start ollama"
    echo "   Or: ollama serve"
fi

echo ""
echo "2. Open WebUI Service:"

# Determine Docker command
DOCKER_CMD="sudo docker"

WEB_URL=""
for port in 3000 8080; do
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
echo "   Restart Ollama: brew services restart ollama"
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
VERIFY_EOF

# Make all scripts executable
chmod +x ~/ollama-launcher.sh
chmod +x ~/ollama-models.sh
chmod +x ~/openwebui-manager.sh
chmod +x ~/ollama-webui-verify.sh

echo "✓ Created ~/ollama-launcher.sh"
echo "✓ Created ~/ollama-models.sh"  
echo "✓ Created ~/openwebui-manager.sh"
echo "✓ Created ~/ollama-webui-verify.sh"
echo ""
echo "Management scripts are now available!"
echo "Test with: ~/llm-manager.sh status"
EOF

chmod +x ~/create_missing_scripts.sh
bash ~/create_missing_scripts.sh
rm ~/create_missing_scripts.sh
