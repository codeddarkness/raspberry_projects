#!/bin/bash
# Pi Monitor Control Script

SERVICE_NAME="pi-monitor"
WEB_PORT="5000"
PI_IP=$(hostname -I | awk '{print $1}')

case $1 in
    start)
        echo "Starting Pi Monitor..."
        sudo systemctl start $SERVICE_NAME
        ;;
    stop)
        echo "Stopping Pi Monitor..."
        sudo systemctl stop $SERVICE_NAME
        ;;
    restart)
        echo "Restarting Pi Monitor..."
        sudo systemctl restart $SERVICE_NAME
        ;;
    status)
        sudo systemctl status $SERVICE_NAME
        ;;
    logs)
        sudo journalctl -u $SERVICE_NAME -f
        ;;
    open)
        echo "Pi Monitor Web Interface:"
        echo "  Local:   http://localhost:$WEB_PORT"
        echo "  Network: http://$PI_IP:$WEB_PORT"
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status|logs|open}"
        echo ""
        echo "Pi Monitor Web Interface:"
        echo "  Local:   http://localhost:$WEB_PORT"
        echo "  Network: http://$PI_IP:$WEB_PORT"
        ;;
esac
