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
