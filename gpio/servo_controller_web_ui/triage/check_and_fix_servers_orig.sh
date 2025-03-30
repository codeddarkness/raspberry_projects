#!/bin/bash

# Define the WebSocket port and Flask port
WEBSOCKET_PORT=8765
FLASK_PORT=5000
LOG_FILE="/home/pi/servo_project/controller/webui/server.log"
FLASK_APP_PATH="/home/pi/servo_project/controller/app.py"

# Function to check if a service is running on a given port
check_service() {
    local port=$1
    if lsof -i :$port > /dev/null; then
        echo "Service running on port $port."
    else
        echo "Service is NOT running on port $port."
        return 1
    fi
}

# Function to attempt to start the WebSocket server
start_websocket() {
    echo "Attempting to start WebSocket server on port $WEBSOCKET_PORT..."
    export FLASK_APP=/home/pi/servo_project/controller/webui/app.py  # Set the correct FLASK_APP path
    cd /home/pi/servo_project/controller
    python3 -m flask run --host=0.0.0.0 --port=$WEBSOCKET_PORT &
    sleep 5
}

# Function to attempt to start Flask server
start_flask() {
    echo "Attempting to start Flask server on port $FLASK_PORT..."
    if [ ! -f "$FLASK_APP_PATH" ]; then
        echo "Error: Flask app file ($FLASK_APP_PATH) not found."
        return 1
    fi
    export FLASK_APP=$FLASK_APP_PATH  # Set the correct FLASK_APP path
    cd /home/pi/servo_project/controller
    python3 -m flask run --host=0.0.0.0 --port=$FLASK_PORT &
    sleep 5
}

# Check if WebSocket server is running on the correct port
echo "Checking WebSocket server status..."
check_service $WEBSOCKET_PORT || start_websocket

# Check if Flask HTTP server is running on the correct port
echo "Checking HTTP server status..."
check_service $FLASK_PORT || start_flask

# Check for 404 and 400 errors in the server log
echo "Checking for 404 and 400 errors in the server log..."
grep "404" $LOG_FILE && echo "404 ERROR: Found 404 errors in the server log."
grep "400" $LOG_FILE && echo "400 ERROR: Found 400 errors in the server log."

# Check for malformed HTTP requests in the server log
echo "Checking for malformed HTTP requests in the server log..."
grep -a "HTTP" $LOG_FILE | grep -i "bad request" && echo "Malformed HTTP request detected."

# Check if the WebSocket and Flask ports are still active
echo "Re-checking WebSocket and Flask server status..."
check_service $WEBSOCKET_PORT
check_service $FLASK_PORT

# Display log file for further inspection if needed
echo "Displaying the last 20 lines of the server log for further inspection:"
tail -n 20 $LOG_FILE

