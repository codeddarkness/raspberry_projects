#!/bin/bash

# Path variables for Flask and WebSocket servers
FLASK_APP_PATH="/home/pi/servo_project/controller/webui/servo_controller.py"
WEB_SOCKET_PORT=8765
FLASK_PORT=5000
SERVER_LOG="/home/pi/servo_project/controller/webui/server.log"

# Check WebSocket server status
echo "Checking WebSocket server status..."
if netstat -tuln | grep ":$WEB_SOCKET_PORT" > /dev/null; then
    echo "WebSocket server is running on port $WEB_SOCKET_PORT."
else
    echo "Service is NOT running on port $WEB_SOCKET_PORT."
    echo "Attempting to start WebSocket server on port $WEB_SOCKET_PORT..."
    # Replace this with your WebSocket server startup command (assuming WebSocket server is part of your Flask app)
    python3 $FLASK_APP_PATH
fi

# Check HTTP server status (Flask server)
echo "Checking HTTP server status..."
if netstat -tuln | grep ":$FLASK_PORT" > /dev/null; then
    echo "Flask server is running on port $FLASK_PORT."
else
    echo "Service is NOT running on port $FLASK_PORT."
    echo "Attempting to start Flask server on port $FLASK_PORT..."
    # Start the Flask server using the correct Python script
    export FLASK_APP=$FLASK_APP_PATH
    flask run --host=0.0.0.0 --port=$FLASK_PORT
fi

# Check for 404 and 400 errors in the server log
echo "Checking for 404 and 400 errors in the server log..."
if grep -q "404" $SERVER_LOG; then
    echo "404 ERROR: Found 404 errors in the server log."
else
    echo "No 404 errors found."
fi

if grep -q "400" $SERVER_LOG; then
    echo "400 ERROR: Found 400 errors in the server log."
else
    echo "No 400 errors found."
fi

# Check for malformed HTTP requests in the server log
echo "Checking for malformed HTTP requests in the server log..."
if grep -q -a "Bad request" $SERVER_LOG; then
    echo "Malformed HTTP request detected."
else
    echo "No malformed HTTP requests detected."
fi

# Re-check WebSocket and Flask server status
echo "Re-checking WebSocket and Flask server status..."
if netstat -tuln | grep ":$WEB_SOCKET_PORT" > /dev/null; then
    echo "WebSocket server is running on port $WEB_SOCKET_PORT."
else
    echo "WebSocket server is NOT running on port $WEB_SOCKET_PORT."
fi

if netstat -tuln | grep ":$FLASK_PORT" > /dev/null; then
    echo "Flask server is running on port $FLASK_PORT."
else
    echo "Flask server is NOT running on port $FLASK_PORT."
fi

# Display last 20 lines of the server log for further inspection
echo "Displaying the last 20 lines of the server log for further inspection:"
tail -n 20 $SERVER_LOG

echo "All checks completed."

