#!/bin/bash
# Open WebUI Troubleshooting Script

DOCKER_CMD="sudo docker"
WEB_URL="http://localhost:3000"

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
if $DOCKER_CMD ps | grep -q open-webui; then
    echo "✓ Container running"
    echo "Container info:"
    $DOCKER_CMD inspect open-webui --format='Network: {{.HostConfig.NetworkMode}}, Ports: {{.HostConfig.PortBindings}}'
else
    echo "✗ Container not running"
    echo "Try: $DOCKER_CMD start open-webui"
fi

echo ""
echo "3. Checking web connectivity..."
if curl -s $WEB_URL > /dev/null; then
    echo "✓ Web interface accessible at $WEB_URL"
else
    echo "✗ Web interface not accessible"
    echo "Checking container logs..."
    $DOCKER_CMD logs --tail=10 open-webui
fi

echo ""
echo "4. Network connectivity test..."
echo "Testing container to Ollama connection..."
if $DOCKER_CMD exec open-webui curl -s http://host.docker.internal:11434/api/tags > /dev/null 2>&1; then
    echo "✓ Container can reach Ollama via host.docker.internal"
elif $DOCKER_CMD exec open-webui curl -s http://docker.for.mac.localhost:11434/api/tags > /dev/null 2>&1; then
    echo "✓ Container can reach Ollama via docker.for.mac.localhost (macOS)"
elif $DOCKER_CMD exec open-webui curl -s http://172.17.0.1:11434/api/tags > /dev/null 2>&1; then
    echo "✓ Container can reach Ollama via Docker gateway"
else
    echo "✗ Container cannot reach Ollama"
    echo "Try recreating container or check Ollama Server URL in WebUI settings"
fi

echo ""
echo "Quick fixes:"
echo "1. Restart both services:"
echo "   $DOCKER_CMD restart open-webui"
echo "   ollama serve"
echo ""
echo "2. Check WebUI Settings > General:"
if [ "macOS" = "Linux" ]; then
    echo "   Ollama Server URL should be http://host.docker.internal:11434"
else
    echo "   Ollama Server URL should be http://host.docker.internal:11434"
fi
echo ""
echo "3. For persistent issues on Linux, try network host mode:"
echo "   $DOCKER_CMD stop open-webui && $DOCKER_CMD rm open-webui"
echo "   $DOCKER_CMD run -d --network=host -v open-webui:/app/backend/data -e OLLAMA_BASE_URL=http://127.0.0.1:11434 --name open-webui --restart always ghcr.io/open-webui/open-webui:main"
