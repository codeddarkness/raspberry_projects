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
